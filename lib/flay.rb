#!/usr/bin/env ruby

# ============================================================================
# flay - A quick and lightweight benchmarking tool for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 13, 2023
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
require "shellwords"
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

    # calculate loops during warmup time
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
    if #{ task.loops.to_i } > 0
      __flay_loops = 0
      __flay_begin = __flay_timer
      while __flay_loops < #{ task.loops.to_i }
        __flay_loops += 1
      end
      __flay_waste = __flay_timer - __flay_begin
    end

    # calculate time spent running our task
    __flay_loops = 0
    __flay_begin = __flay_timer
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

def execute(command, path)
  # puts "", "=" * 78, File.read(path), "=" * 78, ""
  IO.popen(["ruby", path].join(" "), &:read)
  $?.success? or raise
  eval(File.read(path))
end

def scale(show, unit)
  slot = 3
  span = ["G", "M", "K", " ", "m", "µ", "p"]
  show *= 1000.0 and slot += 1 while show < 1.0
  show /= 1000.0 and slot -= 1 while show > 1000.0
  slot.between?(0, 6) or raise "numeric overflow"
  "%6.2f %s%s" % [show, span[slot], unit]
end

def write(file, code)
  file.puts(code)
  file.close
  yield file.path
end

# ==[ Workflow ]==

flay = ARGV.first || "flay-2.rb"
code = ERB.new(DATA.read)

$config = eval(File.read(flay))

es = $config.environments || [{}]
cs = $config.contexts     || [{}]
ts = $config.tasks        || [{}]

# box sections
len = 22
sep = "─" * len
@rt = "┌" + cs.inject("─#{sep}") {|s, c| s += "┬─#{sep}─" } + "┐"
@rm = "├" + cs.inject("─#{sep}") {|s, c| s += "┼─#{sep}─" } + "┤"
@rb = "└" + cs.inject("─#{sep}") {|s, c| s += "┴─#{sep}─" } + "┘"
@cb = "│ %-*.*s│" % [len, len, "Task"]
@cb = cs.inject(@cb) {|s, c| s << " %-*.*s │" % [len, len, c.name("").center(len)] }

es.each_with_index do |e, ei|
  command = ["/Users/shreeve/.asdf/shims/ruby"] # "-C", "somedirectory", "foo bar..."
puts [$0, *ARGV].shelljoin

  puts "", "==[ Environment #{ei + 1}: #{e.name} ]".ljust(75, "="), "" unless e.empty?
  puts @rt
  puts @cb, @rm

  ts.each_with_index do |t, ti|
    print "│ %-*.*s│" % [len, len, t.name]
    cs.each_with_index do |c, ci|
      delay = Tempfile.open(['flay-', '.rb']) do |file|
        t.loops ||= 1e2 # || warmup(e, c, t)
        write(file, code.result(binding).rstrip + "\n") do |path|
          runs, time = execute(command, path)
          rate = runs / time
          print " %s @ %s │" % [scale(time, "s"), scale(rate, "Hz")]
        end
      end
    end
    print "\n"
  end
end
puts @rb

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
