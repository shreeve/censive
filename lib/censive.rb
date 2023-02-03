#!/usr/bin/env ruby

# ============================================================================
# censive - A quick and lightweight CSV handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 2, 2023
#
# • https://crystal-lang.org/api/1.7.2/CSV.html (Crystal's CSV library)
# • https://github.com/ruby/strscan/blob/master/ext/strscan/strscan.c
# • https://github.com/ruby/strscan/issues/50 for details
# • https://github.com/ruby/strscan/pull/52 for code
# ============================================================================
# The goals are:
#
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code base with streamlined logic
# 3. Support for most non-compliant CSV variations
#
# Todo:
#
# 1. Support IO streaming
# 2. Add option to strip whitespace
# 3. Support CSV headers in first row
# 4. Confirm file encodings such as UTF-8, UTF-16, etc.
# ============================================================================

require 'strscan'

class Censive < StringScanner

  def self.writer(obj=nil, **opts, &code)
    case obj
    when String then File.open(path, 'w') {|file| yield new(out: obj, **opts, &code) }
    when IO,nil then new(out: obj, **opts, &code)
    else abort "#{File.basename($0)}: invalid #{obj.class} object in writer"
    end
  end

  def initialize(str=nil,
    drop:  false   , # drop trailing empty fields?
    eol:   "\n"    , # line endings for exports
    excel: false   , # literals(="01") formulas(=A1 + B2); http://bit.ly/3Y7jIvc
    mode:  :compact, # export mode: compact or full
    out:   nil     , # output stream, needs to respond to <<
    quote: '"'     , # quote character
    relax: false   , # relax quote parsing so ,"Fo"o, => ,"Fo""o",
    sep:   ','     , # column separator character
    **opts           # grab bag
  )
    super(str || '')
    reset

    @drop   = drop
    @eol    = eol  .freeze #!# TODO: are the '.freeze' statements helpful?
    @excel  = excel
    @mode   = mode
    @out    = out || $stdout
    @quote  = quote.freeze
    @relax  = relax
    @sep    = sep  .freeze

    @es     = ""   .freeze
    @cr     = "\r" .freeze
    @lf     = "\n" .freeze
    @eq     = "="  .freeze
    @esc    = (@quote * 2).freeze

    @tokens = [@sep,@quote,@cr,@lf,@es,nil]
  end

  def reset(str=nil)
    self.string = str if str
    super()
    @char = peek(1)
    @flag = nil

    @rows = nil
    @cols = @cells = 0
  end

  # ==[ Lexer ]==

  def next_char
    getch
    @char = peek(1) #!# FIXME: not multibyte encoding aware
  end

  def next_token
    case @flag
    when @es then @flag = nil; [@cr,@lf,@es,nil].include?(@char) and return @es
    when @cr then @flag = nil; next_char == @lf and next_char
    when @lf then @flag = nil; next_char
    else          @flag = nil
    end if @flag

    # Excel literals ="0123" and formulas =A1 + B2 (see http://bit.ly/3Y7jIvc)
    if @excel && @char == @eq
      @flag = @eq
      next_char
    end

    if @tokens.include?(@char)
      case @char
      when @quote # consume quoted cell
        match = ""
        while true
          next_char # move past the quote that got us here
          match << (scan_until(/(?=#{@quote})/o) or bomb "unclosed quote")
          case next_char
          when @sep            then @flag = @es; next_char; break
          when @quote          then match << @quote
          when @cr,@lf,@es,nil then break
          else @relax ? match << (@quote + @char) : bomb("invalid character after quote")
          end
        end
        match
      when @sep    then @flag = @es; next_char; @es
      when @cr     then @flag = @cr; nil
      when @lf     then @flag = @lf; nil
      when @es,nil then              nil
      end
    else # consume unquoted cell
      match = scan_until(/(?=#{@sep}|#{@cr}|#{@lf}|\z)/o) or bomb "unexpected character"
      match = @eq + match and @flag = nil if @flag == @eq
      @char = peek(1) #!# FIXME: not multibyte encoding aware
      @char == @sep and @flag = @es and next_char
      match
    end
  end

  def bomb(msg)
    abort "\n#{File.basename($0)}: #{msg} at character #{pos} near '#{string[pos-4,7]}'"
  end

  # ==[ Parser ]==

  def parse
    @rows = []
    while row = next_row
      @rows << row
      count = row.size
      @cols = count if count > @cols
      @cells += count
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

  # returns 2 (must be quoted and escaped), 1 (must be quoted), 0 (neither)
  def grok(str)
    if pos = str.index(/(#{@quote})|#{@sep}|#{@cr}|#{@lf}/o)
      $1 ? 2 : str.index(/#{@quote}/o, pos) ? 2 : 1
    else
      0
    end
  end

  # output a row
  def <<(row)

    # drop trailing empty columns
    row.pop while row.last.empty? if @drop

    #!# FIXME: Excel output needs to protect 0-leading numbers

    s,q = @sep, @quote
    out = case @mode
    when :compact
      case grok(row.join)
      when 0
        row
      when 1
        row.map do |col|
          col.match?(/#{@sep}|#{@cr}|#{@lf}/o) ? "#{q}#{col}#{q}" : col
        end
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

    @out << out + @eol
  end

  def each
    @rows ||= parse
    @rows.each {|row| yield row }
  end

  def export(...)
    out = self.class.writer(...)
    each {|row| out << row }
  end

  def stats
    wide = string.size.to_s.size
    puts "%#{wide}d rows"    % @rows.size
    puts "%#{wide}d columns" % @cols
    puts "%#{wide}d cells"   % @cells
    puts "%#{wide}d bytes"   % string.size
  end
end

if __FILE__ == $0
  raw = DATA.gets("\n\n").chomp
  csv = Censive.new(raw, excel: true)
  csv.export # (sep: "\t", excel: true)
end

__END__
Name,Age,Shoe
Alice,27,5
Bob,33,10 1/2
Charlie or "Chuck",=B2 + B3,9
"Doug E Fresh",="007",10
Subtotal,=sum(B2:B5),="01234"
