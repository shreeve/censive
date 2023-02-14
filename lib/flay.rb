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

def boxlines(main, cols, runs=1)
  [ "┌┬──┐",
    "├┼┬─┤",
    "└┴┴─┘" ]
  .map do |str|
    list = [main, *(cols * runs)]
    list.map.with_index do |col, i|
      chr = str[i < 3 ? i : (i - 1) % cols.size == 0 ? 1 : 2]
      chr + str[3] * (col + 2)
    end.join + str[-1]
  end
end

def stats(list, scope=nil)
  list.map do |item|
    pair = case item
    when :loops then ["runs"     , "times"]
    when :time  then ["time"     , "s"    ]
    when :ips   then ["runs/time", "i/s"  ]
    when :spi   then ["time/runs", "s/i"  ]
    else abort "unknown statistic #{item.inspect}"
    end
    scope ? eval(pair[0], scope) : pair[1]
  end
end

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
show = [ :loops, :time, :ips, :spi ]

code = ERB.new(DATA.read)

$config = eval(File.read(flay))

es = $config.environments || [{}]
cs = $config.contexts     || [{}]
ts = $config.tasks        || [{}]

# drawing
show = [:time, :ips, :spi]
cols = stats(show)
full = cols.map(&:size).sum + cols.size * 11 - 3
wide = [*es.map {|e| e.name("").size}, *ts.map {|t| t.name("").size}].max
@rt, @rm, @rb = boxlines(wide, cols.map {|e| e.size + 8 }, cs.size)

# begin output
puts "```"
puts [$0, *ARGV].shelljoin
puts IO.popen(["ruby", "-v"].join(" "), &:read)

# let 'er rip!
es.each_with_index do |e, ei|
  puts @rt

  command = ["/Users/shreeve/.asdf/shims/ruby"]
  @cb = "│ %-*.*s │" % [wide, wide, e.name(es.size > 1 ? "Env ##{ei + 1}" : "Task")]
  @cb = cs.inject(@cb) {|s, c| s << " %-*.*s │" % [full, full, c.name("").center(full)] }
  puts @cb

  puts @rm
  ts.each_with_index do |t, ti|
    print "│ %-*.*s │" % [wide, wide, t.name]
    cs.each_with_index do |c, ci|
      delay = Tempfile.open(['flay-', '.rb']) do |file|
        loops = t.loops ||= 1e1 # || warmup(e, c, t)
        write(file, code.result(binding).rstrip + "\n") do |path|
          runs, time = execute(command, path)
          vals = stats(show, binding)
          print vals.zip(cols).map {|pair| " %s │" % scale(*pair) }.join
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
