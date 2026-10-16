#include "saved_login_channel.h"
#include "saved_login_store.h"
#include "resource.h"
#include <commctrl.h>
#include <flutter/standard_method_codec.h>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

// Keep native keyboard/accessibility behaviour, but present Bowls branding and
// explicit actions instead of generic Yes/No message boxes.
bool BowlsDialog(HWND owner, const wchar_t* heading, const std::wstring& content,
                 const wchar_t* action, const wchar_t* footer, bool confirm = true) {
  constexpr int kAccept = 100;
  const TASKDIALOG_BUTTON buttons[] = {
      {kAccept, action}, {IDCANCEL, L"Not now"}};
  TASKDIALOGCONFIG config{};
  config.cbSize = sizeof(config);
  config.hwndParent = owner;
  config.hInstance = GetModuleHandleW(nullptr);
  config.dwFlags = static_cast<TASKDIALOG_FLAGS>(
      TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW);
  config.pszWindowTitle = L"Total Leisure Bowls";
  config.pszMainIcon = MAKEINTRESOURCEW(IDI_APP_ICON);
  config.pszMainInstruction = heading;
  config.pszContent = content.c_str();
  config.pszFooter = footer;
  config.cButtons = confirm ? 2 : 1;
  config.pButtons = buttons;
  config.nDefaultButton = confirm ? IDCANCEL : kAccept;
  config.cxWidth = 320;
  int selected = IDCANCEL;
  const HRESULT status = TaskDialogIndirect(&config, &selected, nullptr, nullptr);
  // A failure to display consent must never authorize saving or sign-in.
  return SUCCEEDED(status) && selected == kAccept;
}

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
      BowlsDialog(owner, L"Your saved login is unavailable",
          L"Windows could not access your saved login. You can still sign in manually.",
          L"Continue", L"Total Leisure Bowls | Member sign-in", false);
      result->Error("unavailable", "Windows credential storage is unavailable.");
      return;
    }
    if (call.method_name() == "get") {
      if (status == ERROR_NOT_FOUND || existing.password.empty()) {
        result->Error("no_credentials", "No saved Bowls login for this environment.");
        return;
      }
      const auto prompt = L"Use your saved login to return to the club.\n\n" + existing.identifier;
      if (!BowlsDialog(owner, L"Welcome back to Bowls", prompt,
                       L"Sign in", L"Your login is stored in Windows Credential Manager.")) {
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
    const bool replacing = status == ERROR_SUCCESS && existing.identifier != login.identifier;
    const bool updating = status == ERROR_SUCCESS && !replacing;
    std::wstring prompt = updating
        ? L"Remember your new password for next time.\n\n"
        : L"Make your next visit easier with Use saved login.\n\n";
    prompt += login.identifier;
    if (replacing) {
      prompt += L"\n\nThis replaces the saved login for " + existing.identifier + L".";
    }
    prompt += L"\n\nOnly save on your own Windows account. Anyone using that account can use this login.";
    if (!BowlsDialog(owner,
        replacing ? L"Save a different Bowls login?" :
        updating ? L"Update your saved password?" : L"Save your Bowls login?",
        prompt, replacing ? L"Replace saved login" :
        updating ? L"Update password" : L"Save login",
        L"Protected by Windows Credential Manager on this PC.")) {
      result->Success(Value(false));
      return;
    }
    if (bowls::WriteLogin(target, login) != ERROR_SUCCESS) {
      BowlsDialog(owner, L"Your password could not be saved",
          L"Your account change succeeded, but Windows could not save this password. Enter it manually next time.",
          L"Continue", L"Total Leisure Bowls | Member sign-in", false);
      result->Error("unavailable", "Windows could not save the credential.");
      return;
    }
    result->Success(Value(true));
  });
  return channel;
}
