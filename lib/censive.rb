#!/usr/bin/env ruby

# ==============================================================================
# censive - A quick and lightweight CSV handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Jan 30, 2023
# ==============================================================================
# The goals are:
#
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code base with streamlined method calls
#
# To consider:
#
# 1. Option to support IO streaming
# 2. Option to strip whitespace
# 3. Option to change output line endings
# 4. Option to force quotes in output
# 5. Option to allow reading excel CSV (="Text" for cells)
# 6. Confirm file encodings such as UTF-8, UTF-16, etc.
#
# NOTE: Only getch and scan_until advance strscan's position
# ==============================================================================

require 'strscan'

class Censive < StringScanner

  def self.writer(path, **opts)
    File.open(path, 'w') do |file|
      yield new(out: file, **opts)
    end
  end

  def initialize(str=nil,
    sep:   ','     , # column separator character
    quote: '"'     , # quote character
    out:   nil     , # output IO/file
    mode:  :compact, # export mode: compact or full
    drop:  false   , # enable to drop trailing separators
    eol:   "\n"      # desired line endings for exports
  )
    super(str || '')
    reset

    @sep   = sep  .freeze
    @quote = quote.freeze
    @out   = out
    @mode  = mode
    @drop  = drop
    @eol   = eol.freeze

    @es    = ""   .freeze
    @cr    = "\r" .freeze
    @lf    = "\n" .freeze
    @esc   = (@quote * 2).freeze
  end

  def reset(str=nil)
    self.string = str if str
    super()
    @char  = string[pos]
    @flag  = nil

    @rows  = nil
    @cols  = @cells = 0
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
          when @sep        then @flag = @es; next_char; break
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
      @char == @sep and @flag = @es and next_char
      match
    end
  end

  def bomb(msg)
    abort "#{File.basename($0)}: #{msg} at character #{pos} near '#{string[pos-4,7]}'"
  end

  # ==[ Parser ]==

  def parse
    @rows ||= []
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

  # grok returns: 2 for seps and quotes, 1 for seps only, and 0 for neither
  def grok(str)
    if pos = str.index(/(#{@quote})|#{@sep}/o)
      $1 ? 2 : str.index(/#{@quote}/o, pos) ? 2 : 1
    else
      0
    end
  end

  def <<(row)
    @out or return super

    # most compact export format
    s,q = @sep, @quote
    out = case @mode
    when :compact
      case grok(row.join)
      when 0 then row
      when 1 then row.map {|col| col.include?(s) ? "#{q}#{col}#{q}" : col }
      else
        row.map do |col|
          case grok(col)
          when 0 then col
          when 1 then "#{q}#{col}#{q}"
          else        "#{q}#{col.gsub(q, @esc)}#{q}"
          end
        end
      end
    when :full
      row.map {|col| "#{q}#{col.gsub(q, @esc)}#{q}" }
    end.join(s)

    # drop trailing seps, if specified
    out.gsub!(/#{s}+\z/,'') if @drop

    # write output, using desired line endings
    @out << out + @eol
  end

  def each
    @rows ||= parse
    @rows.each {|row| yield row }
  end

  def stats
    wide = string.size.to_s.size
    puts "%#{wide}d rows"    % @rows.size
    puts "%#{wide}d columns" % @cols
    puts "%#{wide}d cells"   % @cells
    puts "%#{wide}d bytes"   % string.size
  end
end
