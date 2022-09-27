// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "impeller/renderer/backend/metal/command_buffer_mtl.h"

#include "impeller/renderer/backend/metal/blit_pass_mtl.h"
#include "impeller/renderer/backend/metal/compute_pass_mtl.h"
#include "impeller/renderer/backend/metal/render_pass_mtl.h"

namespace impeller {
#if !(defined(TARGET_OS_TV) && TARGET_OS_TV)  
API_AVAILABLE(ios(14.0), macos(11.0))
static NSString* MTLCommandEncoderErrorStateToString(
    MTLCommandEncoderErrorState state) {
  switch (state) {
    case MTLCommandEncoderErrorStateUnknown:
      return @"unknown";
    case MTLCommandEncoderErrorStateCompleted:
      return @"completed";
    case MTLCommandEncoderErrorStateAffected:
      return @"affected";
    case MTLCommandEncoderErrorStatePending:
      return @"pending";
    case MTLCommandEncoderErrorStateFaulted:
      return @"faulted";
  }
  return @"unknown";
}
#endif

static NSString* MTLCommandBufferErrorToString(MTLCommandBufferError code) {
  switch (code) {
    case MTLCommandBufferErrorNone:
      return @"none";
    case MTLCommandBufferErrorInternal:
      return @"internal";
    case MTLCommandBufferErrorTimeout:
      return @"timeout";
    case MTLCommandBufferErrorPageFault:
      return @"page fault";
    case MTLCommandBufferErrorNotPermitted:
      return @"not permitted";
    case MTLCommandBufferErrorOutOfMemory:
      return @"out of memory";
    case MTLCommandBufferErrorInvalidResource:
      return @"invalid resource";
    case MTLCommandBufferErrorMemoryless:
      return @"memory-less";
    default:
      break;
  }

  return [NSString stringWithFormat:@"<unknown> %zu", code];
}

static bool LogMTLCommandBufferErrorIfPresent(id<MTLCommandBuffer> buffer) {
  if (!buffer) {
    return true;
  }

  if (buffer.status == MTLCommandBufferStatusCompleted) {
    return true;
  }

  std::stringstream stream;
  stream << ">>>>>>>" << std::endl;
  stream << "Impeller command buffer could not be committed!" << std::endl;

  if (auto desc = buffer.error.localizedDescription) {
    stream << desc.UTF8String << std::endl;
  }

  if (buffer.error) {
    stream << "Domain: "
           << (buffer.error.domain.length > 0u ? buffer.error.domain.UTF8String
                                               : "<unknown>")
           << " Code: "
           << MTLCommandBufferErrorToString(
                  static_cast<MTLCommandBufferError>(buffer.error.code))
                  .UTF8String
           << std::endl;
  }
#if !(defined(TARGET_OS_TV) && TARGET_OS_TV)
  if (@available(iOS 14.0, macOS 11.0, *)) {
    NSArray<id<MTLCommandBufferEncoderInfo>>* infos =
        buffer.error.userInfo[MTLCommandBufferEncoderInfoErrorKey];
    for (id<MTLCommandBufferEncoderInfo> info in infos) {
      stream << (info.label.length > 0u ? info.label.UTF8String
                                        : "<Unlabelled Render Pass>")
             << ": "
             << MTLCommandEncoderErrorStateToString(info.errorState).UTF8String
             << std::endl;

      auto signposts = [info.debugSignposts componentsJoinedByString:@", "];
      if (signposts.length > 0u) {
        stream << signposts.UTF8String << std::endl;
      }
    }

    for (id<MTLFunctionLog> log in buffer.logs) {
      auto desc = log.description;
      if (desc.length > 0u) {
        stream << desc.UTF8String << std::endl;
      }
    }
  }
#endif
  stream << "<<<<<<<";
  VALIDATION_LOG << stream.str();
  return false;
}

<<<<<<< HEAD
static id<MTLCommandBuffer> CreateCommandBuffer(id<MTLCommandQueue> queue) {
=======
id<MTLCommandBuffer> CreateCommandBuffer(id<MTLCommandQueue> queue) {
#if !(defined(TARGET_OS_TV) && TARGET_OS_TV)
>>>>>>> 063d6c5820 (update to 3.3.1)
  if (@available(iOS 14.0, macOS 11.0, *)) {
    auto desc = [[MTLCommandBufferDescriptor alloc] init];
    // Degrades CPU performance slightly but is well worth the cost for typical
    // Impeller workloads.
    desc.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
    return [queue commandBufferWithDescriptor:desc];
  }
#endif
  return [queue commandBuffer];
}

CommandBufferMTL::CommandBufferMTL(const std::weak_ptr<const Context>& context,
                                   id<MTLCommandQueue> queue)
    : CommandBuffer(context), buffer_(CreateCommandBuffer(queue)) {}

CommandBufferMTL::~CommandBufferMTL() = default;

bool CommandBufferMTL::IsValid() const {
  return buffer_ != nil;
}

void CommandBufferMTL::SetLabel(const std::string& label) const {
  if (label.empty()) {
    return;
  }

  [buffer_ setLabel:@(label.data())];
}

static CommandBuffer::Status ToCommitResult(MTLCommandBufferStatus status) {
  switch (status) {
    case MTLCommandBufferStatusCompleted:
      return CommandBufferMTL::Status::kCompleted;
    case MTLCommandBufferStatusEnqueued:
      return CommandBufferMTL::Status::kPending;
    default:
      break;
  }
  return CommandBufferMTL::Status::kError;
}

bool CommandBufferMTL::OnSubmitCommands(CompletionCallback callback) {
  if (callback) {
    [buffer_
        addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
          [[maybe_unused]] auto result =
              LogMTLCommandBufferErrorIfPresent(buffer);
          FML_DCHECK(result)
              << "Must not have errors during command buffer submission.";
          callback(ToCommitResult(buffer.status));
        }];
  }

  [buffer_ commit];
  [buffer_ waitUntilScheduled];
  buffer_ = nil;
  return true;
}

std::shared_ptr<RenderPass> CommandBufferMTL::OnCreateRenderPass(
    RenderTarget target) {
  if (!buffer_) {
    return nullptr;
  }

  auto pass = std::shared_ptr<RenderPassMTL>(
      new RenderPassMTL(context_, target, buffer_));
  if (!pass->IsValid()) {
    return nullptr;
  }

  return pass;
}

std::shared_ptr<BlitPass> CommandBufferMTL::OnCreateBlitPass() const {
  if (!buffer_) {
    return nullptr;
  }

  auto pass = std::shared_ptr<BlitPassMTL>(new BlitPassMTL(buffer_));
  if (!pass->IsValid()) {
    return nullptr;
  }

  return pass;
}

std::shared_ptr<ComputePass> CommandBufferMTL::OnCreateComputePass() const {
  if (!buffer_) {
    return nullptr;
  }

  auto pass =
      std::shared_ptr<ComputePassMTL>(new ComputePassMTL(context_, buffer_));
  if (!pass->IsValid()) {
    return nullptr;
  }

  return pass;
}

}  // namespace impeller
