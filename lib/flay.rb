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

require "erb"

class Hash
  alias_method :default_lookup, :[]

  def [](key, miss=nil) # key is a symbol
    key?(key) and return default_lookup(key) || miss

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

$config = {
  environments: [
    {
      name: "Environment 1",
      begin: <<~"|".rstrip,
        # environment 1 begin
      |
      end: <<~"|".rstrip,
        # environment 1 end
      |
    },
    {
      name: "Environment 2",
      begin: <<~"|".rstrip,
        # environment 2 begin
      |
      end: <<~"|".rstrip,
        # environment 2 end
      |
    },
  ],

  contexts: [
    {
      name: "Context 1",
      begin: <<~"|".rstrip,
        # context 1 begin
      |
      script: <<~"|".rstrip,
        a = [*1..1e5]
        a.sum
      |
      end: <<~"|".rstrip,
        # context 1 end
      |
    },
    {
      name: "Context 2",
      begin: <<~"|".rstrip,
        # context 2 begin
      |
      end: <<~"|".rstrip,
        # context 2 end
      |
    },
  ],

  tasks: [
    {
      name: "Task 1",
      runs: 35,
      begin: <<~"|".rstrip,
        # task 1 begin
      |
      script: "task 1 script",
      end: <<~"|".rstrip,
        # task 1 end
      |
    },
    {
      name: "Task 2",
      secs: 30,
      begin: <<~"|".rstrip,
        # task 2 begin
      |
      script: "task 2 script",
      end: <<~"|".rstrip,
        # task 2 end
      |
    },
  ],
}

# ==[ Templates ]==

def template_for_warmup(task, code=nil, &block)
  <<~"|"
    #{ section "Warmup for #{task.name}", use: "=-" }

    # ==[ Task begin ]==

    #{ task.begin }

    # ==[ First warmup ]==

    __flay_runs = 0
    __flay_begin = Time.now
    __flay_target = __flay_begin + #{ $config.first_warmup_duration(3) }
    while Time.now < __flay_target

      # ==[ Script begin ]==

      #{ task.script }

      # ==[ Script end ]==

      __flay_runs += 1
    end
    __flay_end = Time.now

    # ==[ Second warmup ]==

    __flay_100ms = (__flay_runs.to_f / (__flay_end - __flay_begin) / 10.0).ceil
    __flay_loops = 0
    __flay_duration = 0.0
    __flay_target = Time.now + #{ $config.second_warmup_duration(6) }
    while Time.now < __flay_target
      __flay_runs = 0
      __flay_begin = Time.now
      while __flay_runs < __flay_100ms

        # ==[ Script begin ]==

        #{ task.script }

        # ==[ Script end ]==

        __flay_runs += 1
      end
      __flay_end = Time.now
      __flay_loops += __flay_runs
      __flay_duration += (__flay_end - __flay_begin)
    end

    # ==[ Task end ]==

    #{ task.end }

    #{ section "Warmup for #{task.name}", use: "-=" }

    # ==[ Write out timestamps ]==

    File.write("/dev/null", [__flay_duration, __flay_loops].inspect)
  |
end

def template_for_task(task, code=nil, &block)
  return yield <<~"|".rstrip
    #{ section task.name, use: "=-" }

    #{ task.begin }
    # #{ "#{task.name } code goes here ***".upcase }
    #{ task.end }

    #{ section task.name, use: "-=" }
  |

  yield <<~"|"
    #{ section task.name, use: "=-" }

    #{ task.begin }

    # ==[ Calculate the duration of a loop of empty runs ]==

    if #{ task.runs } == 1
      __flay_begin_empty = 0
      __flay_end_empty  = 0
    else
      __flay_begin_empty = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      __flay_runs = 0
      while __flay_runs < #{ task.runs } # this empty loop improves accuracy
        __flay_runs += 1
      end
      __flay_end_empty = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # ==[ Calculate the duration of a loop of script runs ]==

    __flay_begin_script = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    __flay_runs = 0
    while __flay_runs < #{ task.runs }

      # ==[ Script begin ]==

      #{ task.script }

      # ==[ Script end ]==

      __flay_runs += 1
    end
    __flay_end_script = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    #{ task.end }

    #{ section task.name, use: "-=" }

    # ==[ Write out timestamps ]==

    __flay_duration = (__flay_end_script - __flay_begin_script) -
                      (__flay_end_empty  - __flay_begin_empty )

    File.write("/dev/null", __flay_duration.inspect)
  |
end

def template_for_context(context, code=nil, &block)
  yield <<~"|"
    #{ section context.name, use: "=-" }

    #{ context.begin }

    #{ code }

    #{ context.end }

    #{ section context.name, use: "-=" }
  |
end

def template_for_environment(environment, code=nil, &block)
  code = yield(code).join("\n")

  code = <<~"|"
    #{ section environment.name, use: "=-" }

    #{ environment.begin }

    #{ code.rstrip }

    #{ environment.end }

    #{ section environment.name, use: "-=" }
  |
end

# ==[ Helpers ]==

def section(text, wide: 78, left: 0, use: "==")
  [
    "# ".ljust(wide, use[ 0]),
    "# #{text}",
    "# ".ljust(wide, use[-1]),
  ].join("\n")
end

def hr(text, wide=78, left=0)
  [ " " * left, "# ==[ ", text, " ]" ].join.ljust(wide, "=")
end

# ==[ Workflow ]==

code = ERB.new(DATA.read)

es = environments = $config.environments
cs = contexts     = $config.contexts
ts = tasks        = $config.tasks

es    .each_with_index do |e, ei|
  cs  .each_with_index do |c, ci|
    ts.each_with_index do |t, ti|
      puts code.result(binding)
    end
  end
end

__END__

# ============================================================================
# Environment <%= ei + 1 %>: <%= e.name %>
#     Context <%= ci + 1 %>: <%= c.name %>
#        Task <%= ti + 1 %>: <%= t.name %>
# ============================================================================

# { environment

<%= e.begin %>

# { context

<%= c.begin %>

# { task

<%= t.begin %>

...

<%= t.end %>

# } task

<%= c.end %>

# } context

<%= e.end %>

# } environment
