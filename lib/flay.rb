#!/usr/bin/env ruby

# ============================================================================
# flay - A quick and lightweight benchmarking tool for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 10, 2023
# ============================================================================
# GOALS:
# 1. Provide a simple way to benchmark code
# 2. Easy to configure and compare results
# 3. Accurately measure times, see http://bit.ly/3ltE7MP
#
# TODO:
# 1. Everything
# ============================================================================

require "erb"
require "shellwords" # TODO: do we really need this?
require "tempfile"

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
      begin: <<~"|".strip,
        ruby_ver = "3.2.0" # environment 1 begin
      |
      end: <<~"|".strip,
        # environment 1 end
      |
    },
    {
      name: "Environment 2",
      begin: <<~"|".strip,
        # environment 2 begin
      |
      end: <<~"|".strip,
        # environment 2 end
      |
    },
  ],

  contexts: [
    {
      name: "Context 1",
      begin: <<~"|".strip,
        require "csv" # context 1 begin
      |
      end: <<~"|".strip,
        # context 1 end
      |
    },
    {
      name: "Context 2",
      begin: <<~"|".strip,
        require "censive" # context 2 begin
      |
      end: <<~"|".strip,
        # context 2 end
      |
    },
  ],

  tasks: [
    {
      name: "Task 1",
      runs: 35,
      begin: <<~"|".strip,
        # task 1 begin
      |
      script: <<~"|",

        # <<<<<
        # task 1 script
        a = [*1..1e5]
        a.sum
        # >>>>>
      |
      end: <<~"|".strip,
        # task 1 end
      |
    },
    {
      name: "Task 2",
      secs: 30,
      begin: <<~"|".strip,
        # task 2 begin
      |
      script: <<~"|".strip,
        a = 0
        1e5.to_i.times {|n| a += n }
        a
      |
      end: <<~"|".strip,
        # task 2 end
      |
    },
  ],
}

# ==[ Templates ]==

def code_for_warmup(task, path)
  <<~"|".strip

    # warmup for #{task.name}"

    #{ task.begin }

    # calculate iterations during warmup time
    __flay_loops = 0
    __flay_begin = __flay_timer
    __flay_until = __flay_begin + #{ $config.warmup(3) }
    while __flay_timer < __flay_until
      #{ "\n" + task.script&.strip }

      __flay_loops += 1
    end
    __flay_delay = __flay_timer - __flay_begin

    File.write(#{ path.inspect }, [__flay_loops, __flay_delay].inspect)

    #{ task.end }
  |
end

def code_for_task(task, path)
  <<~"|".strip
    #{ task.begin }

    # calculate time wasted on loop overhead
    __flay_waste = 0
    __flay_loops = 0
    if __flay_loops > 0
      __flay_loops = 0
      __flay_begin = __flay_timer
      while __flay_loops < #{ task.loops.to_i }
        __flay_loops += 1
      end
      __flay_waste = __flay_timer - __flay_begin
    end

    # calculate time spent running our task
    __flay_begin = __flay_timer
    __flay_loops = 0
    while __flay_loops < #{ task.loops.to_i }
      #{ "\n" + task.script&.strip }

      __flay_loops += 1
    end
    __flay_delay = __flay_timer - __flay_begin

    File.write(#{ path.inspect }, [__flay_loops, __flay_delay].inspect)

    #{ task.end }
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

# ec = es.size
# cc = cs.size
# tc = ts.size

def write(file, code)
  file.puts(code)
  file.close
  yield file.path
end

def execute(command, path)
  # puts File.read(path), "=" * 78
  IO.popen(["ruby", path].shelljoin, &:read)
  $?.success? or raise

  puts body = File.read(path)
  eval(File.read(path))
end

es.each_with_index do |e, ei|
  command = ["/Users/shreeve/.asdf/shims/ruby"] # "-C", "somedirectory", "foo bar..."

  ts.each_with_index do |t, ti|
    cs.each_with_index do |c, ci|
      delay = Tempfile.open(['flay-', '.rb']) do |file|
        t.loops ||= 1e2 # || warmup(e, c, t)
        write(file, code.result(binding)) do |path|
          value = execute(command, path)
        end
      end
    end
  end
end

__END__

# ============================================================================
# Environment <%= ei + 1 %>: <%= e.name %>
#     Context <%= ci + 1 %>: <%= c.name %>
#        Task <%= ti + 1 %>: <%= t.name %>
# ============================================================================

def __flay_timer; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

<%= e.begin %>
<%= c.begin %>

<%= code_for_task(t, file.path) %>

<%= c.end %>
<%= e.end %>
