//
// Copyright 2021 Splunk Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#include <collector/aws/collector.h>

#include <scheduling/interval_scheduler.h>

#include <util/jitter.h>
#include <util/log.h>
#include <util/log_formatters.h>

#include <functional>
#include <stdexcept>
#include <thread>

namespace collector::aws {

namespace {

constexpr auto RECONNECT_DELAY = 5s;
// explicitly using milliseconds for a finer grained jitter
constexpr std::chrono::milliseconds RECONNECT_JITTER = 1s;

} // namespace

AwsCollector::AwsCollector(
    ::uv_loop_t &loop,
    std::string_view hostname,
    AuthzFetcher &authz_fetcher,
    std::chrono::milliseconds aws_metadata_timeout,
    std::chrono::milliseconds heartbeat_interval,
    std::size_t buffer_size,
    config::IntakeConfig intake_config,
    std::chrono::milliseconds poll_interval)
    : loop_(loop),
      connection_(
          hostname,
          loop_,
          aws_metadata_timeout,
          heartbeat_interval,
          std::move(intake_config),
          authz_fetcher,
          buffer_size,
          *this,
          std::bind(&AwsCollector::on_authenticated, this)),
      log_(connection_.writer()),
      enumerator_(log_, connection_.index(), connection_.writer()),
      scheduler_(loop_, std::bind(&AwsCollector::callback, this)),
      poll_interval_(poll_interval)
{}

AwsCollector::~AwsCollector()
{
  ::uv_loop_close(&loop_);
}

void AwsCollector::run_loop()
{
  connection_.connect();

  while (::uv_run(&loop_, UV_RUN_DEFAULT))
    ;

  scheduler_.stop();
}

scheduling::JobFollowUp AwsCollector::callback()
{
  auto result = enumerator_.enumerate();
  connection_.flush();
  return result;
}

void AwsCollector::on_error(int err)
{
  scheduler_.stop();

  enumerator_.free_handles();

  std::this_thread::sleep_for(add_jitter(RECONNECT_DELAY, -RECONNECT_JITTER, RECONNECT_JITTER));
}

void AwsCollector::on_authenticated()
{
  scheduler_.start(poll_interval_, poll_interval_);
}

} // namespace collector::aws
