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
  def +@; Config[self]; end
end

class Config < Hash
  def [](key, miss=nil)
    key?(sym = key.to_sym) and return super(sym) || miss
    ary = key.to_s.split(/(?:[.\/\[]|\][.\/]?)/)
    val = ary.inject(self) do |obj, sub|
      if    obj == self        then super(sub.to_sym)
      elsif obj == nil         then break
      elsif sub =~ /\A-?\d*\z/ then obj[sub.to_i]
      else                          obj[sub.to_sym]
      end
    end or miss
  end

config = {
  name: "My Cool Benchmark",
end

  contexts: [
  ],
  tasks: [

  ],
}
