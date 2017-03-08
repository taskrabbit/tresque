# TResque

Patterns for Resque usage at TaskRabbit

* So work in instance method `work` instead of class method `perform`
* Enqueue hash instead of struct for more flexibility and change management
* Locking based on queue or timing
* Easy way to delay method calls
* Method for registering queue names to centralize ops
* Abstraction so we can move to Sidekiq even easier when that is the goal

## Worker

```ruby
require 'tresque'

module MyEngine
  class ImageProcessor
    include ::TResque::Worker

    inputs :user_id, :size

    def work
      User.find(user_id).upload_image!(size)
    end
  end
end
```

#### Example Usage

```ruby
  MyEngine::ImageProcessor.enqueue(size: "small", user_id: 255)
```

## Queue Management

Say what queues you process

```ruby
require 'tresque'

TResque.register("account") do
  queue :default, 100
  queue :refresh, -5000
end
```

Can put workers in those queues

```
module Account
  class RegularWorker
    include ::TResque::Worker
    # defaults to account_default queue
  end
end

module Account
  class RegularWorker
    include ::TResque::Worker
    queue :refresh # lower priority account_refresh queue
  end
end
```

#### Rake setup

```ruby
require 'resque/tasks'
require 'resque_scheduler/tasks'
require "resque_bus/tasks"

namespace :resque do
  task :setup => [:environment] do
    require 'resque_scheduler'
    require 'resque/scheduler'
    require 'tresque'
  end
  
  task :queues => [:setup] do
    queues = ::TResque::Registry.queues
    ENV["QUEUES"] = queues.join(",")
    puts "TResque: #{ENV["QUEUES"]}"
  end
end

```

Work those queues by priority
```
  $ bundle exec rake resque:queues resque:work
  TResque: account_default, account_refresh
```

## Locking

```ruby
module MyEngine
  class SingletonWorker
    include ::TResque::Worker
    inputs :user_id

    # does not enqueue another worker if this worker with same user_id waiting to be processed
    queue_lock :user_id
  end
end

module MyEngine
  class MutexWorker
    include ::TResque::Worker
    inputs :user_id, :any_other_input

    # does work two of these workers at the same time for the same user_id
    worker_lock :user_id
  end
end
```

Those locks are for the same worker. You can also coordinate across workers using a namespace. Or, in other words, the default namespace is the worker class name but can be overridden. The keys need the same name.

```ruby
module MyEngine
  class FirstWorker
    include ::TResque::Worker
    inputs :user_id

    lock_namespace :user_calculations
    worker_lock :user_id
  end

  class SecondWorker
    include ::TResque::Worker
    inputs :user_id, :other_input

    lock_namespace :user_calculations
    worker_lock :user_id
  end

  class ThirdWorker
    include ::TResque::Worker
    inputs :other_key

    lock_namespace :user_calculations
    worker_lock :user_id

    def user_id
      # can be a method too
      User.find_by_other_key(other_key).id
    end
  end
end
```

## Delay

```ruby
  class User < ::ActiveRecord::Base
    include ::TResque::Delay

    def heavy_lifting
      # stuff in background
    end
    async :heavy_lifting, queue: 'my_queue'

    def other_stuff

    end
  end
```
#### Example Usage

```ruby
  user = User.find(1)

  # Always in the background
  user.heavy_lifting

  # optionally in the background
  user.delay.other_stuff
```

## Notes

Generally based on [qe](https://github.com/fnando/qe).

