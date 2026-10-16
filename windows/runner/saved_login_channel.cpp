#include "saved_login_channel.h"
#include "saved_login_store.h"
#include <flutter/standard_method_codec.h>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

std::wstring Wide(const std::string& text) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result.data(), size);
  return result;
}
std::string Utf8(const std::wstring& text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
      result.data(), size, nullptr, nullptr);
  return result;
}
const std::string* Field(const Map* args, const char* key) {
  if (!args) return nullptr;
  auto found = args->find(Value(key));
  return found == args->end() ? nullptr : std::get_if<std::string>(&found->second);
}
bool ValidHost(const std::string* host) {
  if (!host || host->empty() || host->size() > 253) return false;
  for (char c : *host) {
    if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') &&
        c != '.' && c != '-') return false;
  }
  return true;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<Value>> CreateSavedLoginChannel(
    flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "bowls/saved_login", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](const auto& call, auto result) {
    if (call.method_name() != "get" && call.method_name() != "save") {
      result->NotImplemented();
      return;
    }
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    const auto* host = Field(args, "resource");
    if (!ValidHost(host)) {
      result->Error("invalid_arguments", "Missing app environment.");
      return;
    }
    const auto target = L"TotalLeisure.Bowls/" + Wide(*host) + L"/saved-login";
    bowls::StoredLogin existing;
    const DWORD status = bowls::ReadLogin(target, existing);
    if (status != ERROR_SUCCESS && status != ERROR_NOT_FOUND) {
      MessageBoxW(owner, L"Windows could not access your saved login. You can still sign in manually.",
                  L"Bowls saved login", MB_OK | MB_ICONWARNING);
      result->Error("unavailable", "Windows credential storage is unavailable.");
      return;
    }
    if (call.method_name() == "get") {
      if (status == ERROR_NOT_FOUND || existing.password.empty()) {
        result->Error("no_credentials", "No saved Bowls login for this environment.");
        return;
      }
      const auto prompt = L"Sign in to Bowls as:\n\n" + existing.identifier + L"?";
      if (MessageBoxW(owner, prompt.c_str(), L"Use saved login",
                      MB_OKCANCEL | MB_ICONQUESTION) != IDOK) {
        result->Success();
        return;
      }
      result->Success(Value(Map{{Value("identifier"), Value(Utf8(existing.identifier))},
                                {Value("password"), Value(existing.password)}}));
      return;
    }
    const auto* identifier = Field(args, "identifier");
    const auto* password = Field(args, "password");
    if (!identifier || !password || identifier->empty() || password->empty() ||
        password->size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
      result->Error("invalid_arguments", "Invalid credential.");
      return;
    }
    bowls::StoredLogin login;
    login.identifier = Wide(*identifier);
    login.password = *password;
    if (status == ERROR_SUCCESS && existing.identifier == login.identifier &&
        existing.password == login.password) {
      result->Success(Value(true));
      return;
    }
    std::wstring prompt = status == ERROR_SUCCESS
        ? L"Update the saved Bowls login on this PC for:\n\n"
        : L"Save your Bowls login on this PC for:\n\n";
    prompt += login.identifier;
    if (status == ERROR_SUCCESS && existing.identifier != login.identifier) {
      prompt += L"\n\nThis replaces the saved login for " + existing.identifier + L".";
    }
    prompt += L"\n\nOnly save on your own Windows account. Anyone using that account can use this login.";
    if (MessageBoxW(owner, prompt.c_str(), L"Bowls saved login",
                    MB_YESNO | MB_DEFBUTTON2 | MB_ICONQUESTION) != IDYES) {
      result->Success(Value(false));
      return;
    }
    if (bowls::WriteLogin(target, login) != ERROR_SUCCESS) {
      MessageBoxW(owner, L"Your account change succeeded, but Windows could not save this password. Enter it manually next time.",
                  L"Password not saved", MB_OK | MB_ICONWARNING);
      result->Error("unavailable", "Windows could not save the credential.");
      return;
    }
    result->Success(Value(true));
  });
  return channel;
}
