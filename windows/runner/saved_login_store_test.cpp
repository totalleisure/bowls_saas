#include "saved_login_store.h"
#include <iostream>

int main() {
  const auto prefix = L"TotalLeisure.Bowls.Tests/" +
      std::to_wstring(GetCurrentProcessId()) + L"-" +
      std::to_wstring(GetTickCount64());
  const auto staging = prefix + L"/staging";
  const auto production = prefix + L"/production";
  struct Cleanup {
    std::wstring target;
    ~Cleanup() { CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0); }
  } cleanup{staging};
  auto check = [](bool passed, const char* name) {
    if (!passed) std::cerr << "FAIL: " << name << '\n';
    return passed;
  };
  bowls::StoredLogin read;
  if (!check(bowls::ReadLogin(staging, read) == ERROR_NOT_FOUND, "missing login")) return 1;
  bowls::StoredLogin first;
  first.identifier = L"test-member@example.invalid";
  first.password = "temporary-test-password-\xc3\xa9";
  if (!check(bowls::WriteLogin(staging, first) == ERROR_SUCCESS, "save")) return 1;
  if (!check(bowls::ReadLogin(staging, read) == ERROR_SUCCESS &&
      read.identifier == first.identifier && read.password == first.password, "round trip")) return 1;
  bowls::StoredLogin isolated;
  if (!check(bowls::ReadLogin(production, isolated) == ERROR_NOT_FOUND, "environment isolation")) return 1;
  first.password = "updated-test-password";
  if (!check(bowls::WriteLogin(staging, first) == ERROR_SUCCESS, "update")) return 1;
  bowls::StoredLogin updated;
  if (!check(bowls::ReadLogin(staging, updated) == ERROR_SUCCESS &&
      updated.password == first.password, "updated password read")) return 1;
  first.password.clear();
  if (!check(bowls::WriteLogin(staging, first) == ERROR_INVALID_PARAMETER, "empty rejected")) return 1;
  first.password.assign(CRED_MAX_CREDENTIAL_BLOB_SIZE + 1, 'x');
  if (!check(bowls::WriteLogin(staging, first) == ERROR_INVALID_PARAMETER, "oversize rejected")) return 1;
  if (!check(CredDeleteW(staging.c_str(), CRED_TYPE_GENERIC, 0) != FALSE, "delete")) return 1;
  bowls::StoredLogin removed;
  if (!check(bowls::ReadLogin(staging, removed) == ERROR_NOT_FOUND, "deleted login")) return 1;
  std::cout << "PASS: Windows Credential Manager save/read/update/isolation/validation/delete\n";
  return 0;
}
