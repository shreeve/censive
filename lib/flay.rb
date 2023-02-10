#!/usr/bin/env ruby

# ============================================================================
# flay - A quick and lightweight benchmarking tool for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 9, 2023
# ============================================================================
# GOALS:
# 1. Provide a simple way to benchmark various code
# 2. Easy to configure and start comparing results
# 3. Accurately measure time and speed metrics, see http://bit.ly/3ltE7MP
#
# TODO:
# 1. Everything
# ============================================================================

class Hash
  alias_method :default_lookup, :[]

  def [](key, miss=nil)
    key?(key) and return default_lookup(key)
    key?(sym = key.to_sym) and return default_lookup(sym) || miss
    ary = key.to_s.split(/(?:[.\/\[]|\][.\/]?)/)
    val = ary.inject(self) do |obj, sub|
      if    obj == self        then default_lookup(sub.to_sym)
      elsif obj == nil         then break
      elsif sub =~ /\A-?\d*\z/ then obj[sub.to_i]
      else                          obj[sub.to_sym]
      end
    end or miss
  end

  def method_missing(name, *args)
    name =~ /=$/ ? send(:[]=, $`.to_sym, *args) : send(:[], name, *args)
  end
end

config = {
  environments: [
    {
      name: "Environment 1",
      before: <<~"|",
        # Environment 1 before
      |
      after: <<~"|",
        # Environment 1 after
      |
    },
    {
      name: "Environment 2",
      before: <<~"|",
        # Environment 1 before
      |
      after: <<~"|",
        # Environment 1 after
      |
    },
  ],

  contexts: [
    {
      name: "Context 1",
      before: <<~"|",
        # context 1 before
      |
      script: <<~"|",
        a = [*1..1e5]
        a.sum
      |
      after: <<~"|",
        # context 1 after
      |
    },
    {
      name: "Context 2",
      before: <<~"|",
        # context 2 before
      |
      after: <<~"|",
        # context 2 after
      |
    },
  ],

  tasks: [
    {
      name: "Task 1",
      runs: 35,
      before: <<~"|",
        # Task 1 before
      |
      after: <<~"|",
        # Task 1 after
      |
    },
    {
      name: "Task 2",
      secs: 30,
      before: <<~"|",
        # Task 2 before
      |
      after: <<~"|",
        # Task 2 after
      |
    },
  ],
}

# ==[ Helpers ]==

def wrapper(object, type=nil)
  puts case type
  when :environment then template_for_environment object
  when :context     then template_for_context     object
  when :task        then template_for_task        object
  else                   section                  object
  end
end

def wrap(list, type=nil, **opts)
  list.each do |item|
    wrapper(item, type)
    yield item
  end
end

def section(text, wide=78, left=0)
  [
    "# ".ljust(wide, "="),
    "# #{text}",
    "# ".ljust(wide, "="),
  ].join("\n")
end

def hr(text, wide=78, left=0)
  [ " " * left, "# ==[ ", text, " ]" ].join.ljust(wide, "=")
end

# ==[ Templates ]==

def template_for_environment(environment)
  <<~"|"
    #{ section "Environment: #{environment.name} " }

    # ==[ Code before environment ]==

    #{ environment.before }
  |
end

def template_for_context(context)
  <<~"|"
    #{ section "Context: #{context.name} " }

    # ==[ Code before context ]==

    #{ context.before }
  |
end

def template_for_task(task)
  <<~"|"
    #{ section "Task: #{task.name} " }

    # ==[ Code before task ]==

    #{ task.before }

    # ==[ Calculate the duration of a loop of empty runs ]==

    if #{ task.runs } == 1
      __flay_before_empty = 0
      __flay_after_empty  = 0
    else
      __flay_before_empty = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      __flay_runs = 0
      while __flay_runs < #{ task.runs } # this empty loop improves accuracy
        __flay_runs += 1
      end
      __flay_after_empty = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # ==[ Calculate the duration of a loop of script runs ]==

    __flay_before_script = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    __flay_runs = 0
    while __flay_runs < #{ task.runs }

      # ==[ Before script ]==

      #{ task.script }

      # ==[ After script ]==

      __flay_runs += 1
    end
    __flay_after_script = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # ==[ Code after task ]==

    #{ task.after }

    # ==[ Write out timestamps ]==

    __flay_duration = (__flay_after_script - __flay_before_script) -
                      (__flay_after_empty  - __flay_before_empty )

    File.write("/dev/null", __flay_duration.inspect)
  |
end

def template_for_warmup(task)
  <<~"|"
    #{ section "Warmup for task: #{task.name} " }

    # ==[ Code before task ]==

    #{ task.before }

    # ==[ First warmup ]==

    __flay_runs = 0
    __flay_before = Time.now
    __flay_target = __flay_before + #{ $config.first_warmup_duration(3) }
    while Time.now < __flay_target

      # ==[ Before script ]==

      #{ task.script }

      # ==[ After script ]==

      __flay_runs += 1
    end
    __flay_after = Time.now

    # ==[ Second warmup ]==

    __flay_100ms = (__flay_runs.to_f / (__flay_after - __flay_before) / 10.0).ceil
    __flay_loops = 0
    __flay_duration = 0.0
    __flay_target = Time.now + #{ $config.second_warmup_duration(6) }
    while Time.now < __flay_target
      __flay_runs = 0
      __flay_before = Time.now
      while __flay_runs < __flay_100ms

        # ==[ Before script ]==

        #{ task.script }

        # ==[ After script ]==

        __flay_runs += 1
      end
      __flay_after = Time.now
      __flay_loops += __flay_runs
      __flay_duration += (__flay_after - __flay_before)
    end

    # ==[ Code after task ]==

    #{ task.after }

    # ==[ Write out timestamps ]==

    File.write("/dev/null", [__flay_duration, __flay_loops].inspect)
  |
end

# ==[ Workflow ]==

environments = config.environments
contexts     = config.contexts
tasks        = config.tasks

wrap(environments, :environment) do |environment|
  wrap(tasks, :task) do |task|
    wrap(contexts, :context) do |context|
    end
  end
end
