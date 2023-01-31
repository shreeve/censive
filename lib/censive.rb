#!/usr/bin/env ruby

# ==============================================================================
# censive - A quick and lightweight CVS handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Jan 30, 2023
# ==============================================================================
# The goals are:
#
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code base with streamlined method calls
# 3. Eventually support IO streaming
#
# NOTE: Only getch and scan_until advance strscan's position
# ==============================================================================

require 'strscan'

class Censive < StringScanner
  def initialize(string, sep: ',', quote: '"')
    super(string)
    reset

    @sep   = sep  .freeze
    @quote = quote.freeze

    @es    = ""   .freeze
    @cr    = "\r" .freeze
    @lf    = "\n" .freeze
  end

  def reset
    super
    @char  = string[pos]
    @flag  = nil
  end

  # ==[ Lexer ]==

  def next_char
    getch
    @char = string[pos]
  end

  def next_token
    case @flag
    when @es then @flag = nil; [@cr,@lf,nil].include?(@char) and return @es
    when @cr then @flag = nil; next_char == @lf and next_char
    when @lf then @flag = nil; next_char
    end if @flag

    if [@sep,@quote,@cr,@lf,nil].include?(@char)
      case @char
      when @quote # consume_quoted_cell
        match = ""
        while true
          getch # consume the quote (optimized by not calling next_char)
          match << (scan_until(/(?=#{@quote})/o) or bomb "unclosed quote")
          case next_char
          when @sep        then next_char; break
          when @quote      then match << @quote
          when @cr,@lf,nil then break
          else bomb "unexpected character after quote"
          end
        end
        match
      when @sep then @flag = @es; next_char; @es
      when @cr  then @flag = @cr; nil
      when @lf  then @flag = @lf; nil
      when nil  then nil
      end
    else # consume_unquoted_cell
      match = scan_until(/(?=#{@sep}|#{@cr}|#{@lf}|\z)/o) or bomb "unexpected character"
      @char = string[pos]
      @char == @sep and next_char
      match
    end
  end

  def bomb(msg)
    abort "censive: #{msg} at character #{pos} near '#{string[pos-4,7]}'"
  end

  # ==[ Parser ]==

  def parse
    @rows = []
    @cols = @cells = 0
    while row = next_row
      @rows << row
      size = row.size
      @cols = size if size > @cols
      @cells += size
    end
    @rows
  end

  def next_row
    token = next_token or return
    row = [token]
    row << token while token = next_token
    row
  end

  # ==[ Helpers ]==

  def stats
    wide = string.size.to_s.size
    puts "%#{wide}d rows"    % @rows.size
    puts "%#{wide}d columns" % @cols
    puts "%#{wide}d cells"   % @cells
    puts "%#{wide}d bytes"   % string.size
  end
end
