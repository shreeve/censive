#!/usr/bin/env ruby

# ============================================================================
# winr - A quick and lightweight benchmarking tool for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 14, 2023
# ============================================================================
# GOALS:
# 1. Provide a simple way to benchmark code
# 2. Easy to configure and compare results
# 3. Accurately measure times, see http://bit.ly/3ltE7MP
#
# TODO:
# 1. Enable YAML config files
# ============================================================================

trap("INT" ) { abort "\n" }

require "erb"
require "optparse"
require "shellwords"
require "tempfile"

OptionParser.new.instance_eval do
  @banner  = "usage: #{program_name} [options] <dir ...>"

  on "-c"               , "--[no-]color", "Enable color output (default is true)", TrueClass
  on "-d"               , "--debug"     , "Enable debug mode", TrueClass
  on "-h"               , "--help"      , "Show help and command usage" do Kernel.abort to_s; end
  on "-i <count>"       , "--iterations", "Force the number of iterations for each task", Integer
  on "-r"               , "--reverse"   , "Show contexts vertically and tasks horizontally", TrueClass
  on "-s <time,ips,spi>", "--stats "    , "Comma-separated list of stats (loops, time, ips, spi)"
  on "-v"               , "--verbose"   , "Show command, version details, and markdown backticks", TrueClass

  separator <<~"end"

      Available statistics:

        ips      iterations per second
        loops    number of iterations
        spi      seconds for iteration
        time     time to run all iterations
  end

  self
end.parse!(into: opts={}) rescue abort($!.message)

# option munging
ansi =  opts[:color]; ansi = true if ansi.nil?
hack =  opts[:debug]
hush = !opts[:verbose]
runs =  opts[:iterations]; abort "invalid number of runs" if runs && runs < 1
show =  opts[:stats] || "time,ips,spi"
show =  show.downcase.scan(/[a-z]+/i).uniq & %w[ ips loops spi time ]
swap = !opts[:reverse]

# option errors
show.empty? and abort "invalid list of statistics #{opts[:stats].inspect}"

# ==[ Define some constants, ansi codes, and make hashes more flexible ]==

Infinity = 1.0 / 0
Overflow = "\n\nERROR: numeric overflow"

module Ansi
  refine String do
    $ansi = <<~"".scan(/(\d+)(?:\/(\d+))?=(\w+)/).inject({}) do |ansi, (code, undo, name)|
      0=reset 1/22=bold 2/22=dim 3/23=italic 4/24=under 5/25=blink 7/27=inverse 9/29=strike
      30=black 31=red 32=green 33=yellow 34=blue 35=magenta 36=cyan 37=white 39=default
      40=black 41=red 42=green 43=yellow 44=blue 45=magenta 46=cyan 47=white 49=default

      ansi[name +                       "_off"     ] = undo if undo
      ansi[name + (code[0,2] =~ /4\d/ ? "_bg" : "")] = code
      ansi
    end
    def ansi (*list); list.map {|code| "\e[#{$ansi[code.to_s] || 0}m"}.join + self; end
    def ansi!(*list); ansi(*list) + "\e[0m"; end
  end
end

using Ansi

module FlexHash
  refine Hash do
    alias_method :default_lookup, :[]

    def [](key, miss=nil) # method_missing calls this with key as a symbol
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
  end
end

using FlexHash

class Hash
  def method_missing(name, *args)
    name =~ /=$/ ? send(:[]=, $`.to_sym, *args) : send(:[], name, *args)
  end
end

# ==[ Templates ]==

def compile(task, path)
  <<~"|".strip
    #{ task.begin }

    # number of loops requested
    __winr_iters = #{ task.loops.to_i }

    # calculate loops if not supplied
    if __winr_iters == 0
      __winr_until = __winr_timer + #{ $config.warmup(3) }
      while __winr_timer < __winr_until
        #{ task.script&.strip }
        __winr_iters += 1
      end
    end

    # calculate time wasted on loop overhead
    __winr_waste = 0
    __winr_loops = 0
    __winr_begin = __winr_timer
    while __winr_loops < __winr_iters
      __winr_loops += 1
    end
    __winr_waste = __winr_timer - __winr_begin

    # calculate time spent running our task
    __winr_loops = 0
    __winr_begin = __winr_timer
    while __winr_loops < __winr_iters
      #{ task.script&.strip }
      __winr_loops += 1
    end
    __winr_delay = __winr_timer - __winr_begin

    File.write(#{ path.inspect }, [__winr_loops, __winr_delay - __winr_waste].inspect)

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

def execute(command, path)
  IO.popen(["ruby", path].join(" "), &:read)
  $?.success? or raise
  eval(File.read(path))
end

def scale(show, unit)
  slot = 3
  span = ["G", "M", "K", " ", "m", "µ", "p"]
  [0, Infinity].include?(show) and abort Overflow
  show *= 1000.0 and slot += 1 while show > 0 && show < 1.0
  show /= 1000.0 and slot -= 1 while show >= 1000.0
  slot.between?(0, 6) or abort Overflow
  "%6.2f %s%s" % [show, span[slot], unit]
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

def write(file, data)
  file.puts(data)
  file.close
  yield file.path
end

# ==[ Workflow ]==

# read the winr script
winr = ARGV.first or abort "missing winr script"
tmpl = ERB.new(DATA.read)

# grok the config
$config = eval(File.read(winr))
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
puts "```", [$0, *ARGV].shelljoin, "" unless hush

# loop over environment(s)
es.each_with_index do |e, ei|
  puts IO.popen(["ruby", "-v"].join(" "), &:read) unless hush
  puts rt

  command = ["/usr/bin/env ruby"]

  # loop over context(s) and task(s)
  ys, xs = swap ? [ts, cs] : [cs, ts]

  # row: content, header
  rc = "Task" # or "Context"
  rh = "│ %-*.*s │" % [wide, wide, e.name(es.size > 1 ? "Env ##{ei + 1}" : rc)]
  rh = xs.inject(rh) {|s, x| s << " %-*.*s │" % [full, full, x.name("Results").center(full)] }
  puts rh, rm

  ys.each_with_index do |y, yi|
    print "│ %-*.*s │" % [wide, wide, y.name("Results")]
    xs.each_with_index do |x, xi|
    t, ti, c, ci = swap ? [y, yi, x, xi] : [x, xi, y, yi]
      delay = Tempfile.open(['winr-', '.rb']) do |file|
        t.loops = runs if runs
        code = tmpl.result(binding).rstrip + "\n"
        write(file, code) do |path|
          runs, time = execute(command, path)
          t.loops ||= runs
          vals = stats(show, binding)
          rank << [runs/time, ei, ci, ti]
          print vals.zip(cols).map {|pair| " %s │" % scale(*pair) }.join
        end
        puts "", code, "=" * 78 if hack
      end
    end
    print "\n"
  end
  puts rb, ""
end

# show the comparison
rank.sort! {|a, b| b[0] <=> a[0] }
fast = rank.first[0]
slow = rank.last[0]
pict = "%.2fx slower"
room = (pict % [fast / slow]).size
cols = [11, room, 6]
cols.pop if (es.size == 1) && (cs.size == 1)
full = cols.sum + (cols.size - 1) * 3
rt, rm, rb = boxlines(wide, cols)
rh = "│ %-*.*s │" % [wide, wide, "Rank"]
rh << " %-*.*s │" % [full, full, "Performance".center(full)]

puts rt, rh, rm
flip = cs.size > 1 && ts.size == 1
rank.each do |ips, ei, ci, ti|
  name = (flip ? cs[ci] : ts[ti]).name
  print "│ %-*.*s │ %s │ " % [wide, wide, name, scale(ips, "i/s")]
  if ips.round(2) == fast.round(2)
    text = "fastest".center(room)
    print ansi ? text.ansi!(:green, :bold) : text
  else
    print  "%*.*s" % [room, room, pict % [fast/ips]]
  end
  print " │ %-6s" % ([ei+1,ci+1,ti+1] * "/") if cols.size > 2
  print " │\n"
end
puts rb
puts "```" unless hush

__END__

# ============================================================================
# Environment <%= ei + 1 %>: <%= e.name %>
#     Context <%= ci + 1 %>: <%= c.name %>
#        Task <%= ti + 1 %>: <%= t.name %>
# ============================================================================

trap("INT") { exit }

# def __winr_timer; Process.clock_gettime(Process::CLOCK_MONOTONIC); end
def __winr_timer; Time.now.to_f; end

<%= e.begin %>
<%= c.begin %>

<%= compile(t, file.path) %>

<%= c.end %>
<%= e.end %>
