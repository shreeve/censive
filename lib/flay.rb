#!/usr/bin/env ruby

# ============================================================================
# flay - A quick and lightweight benchmarking tool for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 9, 2023
# ============================================================================
# GOALS:
# 1. Provide a simple way to benchmark different code
# 2. Easy to configure and quickly compare code
#
# TODO:
# 1. Everything
# ============================================================================

class Hash
  alias_method :default_lookup, :[]

  def [](key, miss=nil)
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
    name !~ /=$/ ? self[name, *args] : self[$`.to_sym] = args.first
  end
end

config = {
  environments: [
    {
      name: "Environment 1",
      before: <<~'|',
        # Environment 1 before
      |
      after: <<~'|',
        # Environment 1 after
      |
    },
    {
      name: "Environment 2",
      before: <<~'|',
        # Environment 1 before
      |
      after: <<~'|',
        # Environment 1 after
      |
    },
  ],

  contexts: [
    {
      name: "Context 1",
      before: <<~'|',
        # context 1 before
      |
      script: <<~'|',
        a = [*1..1e5]
        a.sum
      |
      after: <<~'|',
        # context 1 after
      |
    },
    {
      name: "Context 2",
      before: <<~'|',
        # context 2 before
      |
      after: <<~'|',
        # context 2 after
      |
    },
  ],

  tasks: [
    {
      name: "Task 1",
      before: <<~'|',
        # Task 1 before
      |
      after: <<~'|',
        # Task 1 after
      |
    },
    {
      name: "Task 2",
      before: <<~'|',
        # Task 2 before
      |
      after: <<~'|',
        # Task 2 after
      |
    },
  ],
}

# ==[ Helpers ]==

def wrapper(object)
  puts <<~"end"

    # #{ "=" * 70 }
    # #{object.name}
    # #{ "=" * 70 }

    #{object.before }
  end
end

# ==[ Workflow ]==

environments = config.environments
contexts     = config.contexts
tasks        = config.tasks

environments.each do |environment|
  wrapper(environment)
  contexts.each do |context|
    wrapper(context)
    tasks.each do |task|
      wrapper(task)
    end
  end
end
