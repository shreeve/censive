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
# 1. Implement proper display of results
# 2. Implement some magic so the config file is very easy to populate
# ============================================================================

require "erb"
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

# ==[ Templates ]==

def code_for_warmup(task, path)
  <<~"|".strip
    # warmup for #{task.name}"

    #{ task.begin }

    # calculate iterations during warmup time
    __flay_begin = __flay_timer
    __flay_until = __flay_begin + #{ $config.warmup(3) }
    __flay_loops = 0
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

def write(file, code)
  file.puts(code)
  file.close
  yield file.path
end

def execute(command, path)
  # puts File.read(path), "=" * 78
  IO.popen(["ruby", path].join(" "), &:read)
  $?.success? or raise
  eval(File.read(path))
end

# ==[ Workflow ]==

flay = "flay-1.rb"

$config = eval(File.read(flay))

code = ERB.new(DATA.read)

es = environments = $config.environments
cs = contexts     = $config.contexts
ts = tasks        = $config.tasks

# calculate this based on the names and widths of tasks and contexts
@cb = "            Context 1                Context 2"

es.each_with_index do |e, ei|
  command = ["/Users/shreeve/.asdf/shims/ruby"] # "-C", "somedirectory", "foo bar..."
  puts "", "# ==[ #{e.name} ]".ljust(78, "="), ""
  puts @cb
  ts.each_with_index do |t, ti|
    print "Task #{ti + 1}: "
    cs.each_with_index do |c, ci|
      delay = Tempfile.open(['flay-', '.rb']) do |file|
        t.loops ||= 1e2 # || warmup(e, c, t)
        write(file, code.result(binding)) do |path|
          runs, time = execute(command, path)
          rate = runs / time
          print "    %.2f secs @ %.2f Hz" % [time, rate]
        end
      end
    end
    print "\n"
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
