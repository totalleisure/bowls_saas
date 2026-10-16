#ifndef RUNNER_SAVED_LOGIN_STORE_H_
#define RUNNER_SAVED_LOGIN_STORE_H_

#include <windows.h>
#include <wincred.h>
#include <string>

namespace bowls {
// Local Windows-user storage, never app preferences or an unencrypted file.
struct StoredLogin {
  std::wstring identifier;
  std::string password;
  ~StoredLogin() {
    if (!password.empty()) SecureZeroMemory(password.data(), password.size());
  }
};

inline DWORD ReadLogin(const std::wstring& target, StoredLogin& login) {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
    return GetLastError();
  }
  login.identifier = credential->UserName ? credential->UserName : L"";
  if (credential->CredentialBlobSize) {
    login.password.assign(reinterpret_cast<char*>(credential->CredentialBlob),
                          credential->CredentialBlobSize);
    SecureZeroMemory(credential->CredentialBlob, credential->CredentialBlobSize);
  }
  CredFree(credential);
  return ERROR_SUCCESS;
}

inline DWORD WriteLogin(const std::wstring& target, const StoredLogin& login) {
  if (login.identifier.empty() || login.password.empty() ||
      login.password.size() > CRED_MAX_CREDENTIAL_BLOB_SIZE ||
      login.identifier.size() > CRED_MAX_USERNAME_LENGTH) {
    return ERROR_INVALID_PARAMETER;
  }
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(target.c_str());
  credential.UserName = const_cast<wchar_t*>(login.identifier.c_str());
  credential.CredentialBlobSize = static_cast<DWORD>(login.password.size());
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(
      const_cast<char*>(login.password.data()));
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  return CredWriteW(&credential, 0) ? ERROR_SUCCESS : GetLastError();
}
}  // namespace bowls
#endif
