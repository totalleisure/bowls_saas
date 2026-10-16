#ifndef RUNNER_SAVED_LOGIN_CHANNEL_H_
#define RUNNER_SAVED_LOGIN_CHANNEL_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateSavedLoginChannel(flutter::BinaryMessenger* messenger, HWND owner);
#endif
