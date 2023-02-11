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
      script: "# task 1 script",
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
      script: "# task 2 script",
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

    # ==[ Warmup ]==

    __flay_loops = 0
    __flay_begin = __flay_timer
    __flay_until = __flay_begin + #{ $config.warmup(3) }

    while __flay_timer < __flay_until

      # ==[ Script begin ]==

      #{ task.script }

      # ==[ Script end ]==

      __flay_loops += 1
    end

    __flay_delay = __flay_timer - __flay_begin

    # ==[ Task end ]==

    #{ task.end }

    #{ section "Warmup for #{task.name}", use: "-=" }

    # ==[ Write out timestamps ]==

    File.write("/dev/null", [__flay_loops, __flay_delay].inspect)
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

    # ==[ Calculate time wasted on loop overhead ]==

    __flay_waste == 0
    __flay_loops = #{ task.loops.to_i }

    if __flay_loops > 0
      __flay_loops = 0
      __flay_begin = __flay_timer
      while __flay_loops < __flay_loops
        __flay_loops += 1
      end
      __flay_waste = __flay_timer - __flay_begin
    end

    # ==[ Calculate time looping over our task ]==

    __flay_begin = __flay_timer
    while __flay_loops < __flay_loops

      # ==[ Script begin ]==

      #{ task.script }

      # ==[ Script end ]==

      __flay_loops += 1
    end
    __flay_delay = __flay_timer - __flay_begin

    # ==[ Task end ]==

    #{ task.end }

    #{ section task.name, use: "-=" }

    # ==[ Write out timestamps ]==

    File.write("/dev/null", [__flay_loops, __flay_delay].inspect)
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
  ts  .each_with_index do |t, ti|
    cs.each_with_index do |c, ci|
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

def __flay_timer
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

<%= e.begin %>
<%= c.begin %>
<%= t.begin %>
<%= t.script %>
<%= t.end %>
<%= c.end %>
<%= e.end %>
