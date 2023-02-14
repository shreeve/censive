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
# 1. Implement full display of results
# 2. Implement some magic so the config file is very easy to populate
# ============================================================================

require "erb"
require "optparse"
require "shellwords"
require "tempfile"

OptionParser.new.instance_eval do
  @banner  = "usage: #{program_name} [options] <dir ...>"

  on "-i <count>"       , "--iterations", "Force the number of iterations for each task", Integer
  on "-h"               , "--help"      , "Show help and command usage" do Kernel.abort to_s; end
  on "-r"               , "--reverse"   , "Show contexts vertically and tasks horizontally", TrueClass
  on "-s <time,ips,spi>", "--stats "    , "Comma-separated list of stats (loops, time, ips, spi)"
  separator <<~"end"

      Available statistics:

        ips      iterations per second
        loops    number of iterations
        spi      seconds for iteration
        time     time to run all iterations
  end

  self
end.parse!(into: opts={}) rescue abort($!.message)

# runs = opts[:iterations]
runs = opts[:iterations]; abort "invalid number of runs" if runs && runs < 1
show = opts[:stats] || "time,ips,spi"
show = show.downcase.scan(/[a-z]+/i).uniq & %w[ ips loops spi time ]
show.empty? and abort "invalid list of statistics #{opts[:stats].inspect}"
swap = !opts[:reverse]

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
      chr = str[i < 2 ? i : (i - 1) % cols.size == 0 ? 1 : 2]
      chr + str[3] * (col + 2)
    end.join + str[-1]
  end
end

def stats(list, scope=nil)
  list.map do |item|
    pair = case item
    when "loops" then ["runs"     , "times"]
    when "time"  then ["time"     , "s"    ]
    when "ips"   then ["runs/time", "i/s"  ]
    when "spi"   then ["time/runs", "s/i"  ]
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

# read the flay script
flay = ARGV.first or abort "missing flay script"
code = ERB.new(DATA.read)

# grok the config
$config = eval(File.read(flay))
es = $config.environments || [{}]
cs = $config.contexts     || [{}]
ts = $config.tasks        || [{}]

# box drawing
cols = stats(show)
full = cols.map(&:size).sum + cols.size * 11 - 3
wide = [*es.map {|e| e.name("").size}, *ts.map {|t| t.name("").size}].max
rank = []

# row: top, middle, bottom
rt, rm, rb = boxlines(wide, cols.map {|e| e.size + 8 }, (swap ? cs : ts).size)

# begin output
puts "```"
puts [$0, *ARGV].shelljoin
puts IO.popen(["ruby", "-v"].join(" "), &:read)

# loop over environment(s)
es.each_with_index do |e, ei|
  puts rt

  command = ["/Users/shreeve/.asdf/shims/ruby"]

  # loop over context(s) and task(s)
  ys, xs = swap ? [ts, cs] : [cs, ts]

  # row: content, header
  rc = "Task" # or "Context"
  rh = "│ %-*.*s │" % [wide, wide, e.name(es.size > 1 ? "Env ##{ei + 1}" : rc)]
  rh = xs.inject(rh) {|s, x| s << " %-*.*s │" % [full, full, x.name("").center(full)] }
  puts rh, rm

  ys.each_with_index do |y, yi|
    print "│ %-*.*s │" % [wide, wide, y.name]
    xs.each_with_index do |x, xi|
    t, ti, c, ci = swap ? [y, yi, x, xi] : [x, xi, y, yi]
      delay = Tempfile.open(['flay-', '.rb']) do |file|
        t.loops = runs if runs # || warmup(e, c, t)
        t.loops ||= 1
        write(file, code.result(binding).rstrip + "\n") do |path|
          runs, time = execute(command, path)
          vals = stats(show, binding)
          rank << [runs/time, ei, ci, ti]
          print vals.zip(cols).map {|pair| " %s │" % scale(*pair) }.join
        end
      end
    end
    print "\n"
  end
  puts rb
end

# show the comparison
rank.sort! {|a, b| b[0] <=> a[0] }
fast = rank.first[0]
slow = rank.last[0]
pict = "%.2fx slower"
last = (pict % slow).size
cols = [11, last, 6]
full = cols.sum + (cols.size - 1) * 3
rt, rm, rb = boxlines(wide, cols)
rh = "│ %-*.*s │" % [wide, wide, "Rank"]
rh << " %-*.*s │" % [full, full, "Performance".center(full)]

puts "", rt, rh, rm
rank.each do |ips, ei, ci, ti|
  y = swap ? cs[ci] : ts[ti]
  print "│ %-*.*s │ %s │ " % [wide, wide, y.name, scale(ips, "i/s")]
  if ips == fast
    print "fastest".center(last)
  else
    print  "%*.*s" % [last, last, pict % [fast/ips]]
  end
  print " │ %-6s │\n" % ([ei+1,ci+1,ti+1] * "/")
end
puts rb
puts "```"

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
