#!/usr/bin/env ruby

# ============================================================================
# censive - A quick and lightweight CSV handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 4, 2023
#
# https://crystal-lang.org/api/1.7.2/CSV.html (Crystal's CSV library)
# https://github.com/ruby/strscan/blob/master/ext/strscan/strscan.c
# https://github.com/ruby/strscan/issues/53 for details
# https://github.com/ruby/strscan/pull/54 for code
# ============================================================================
# GOALS:
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code base with streamlined logic
# 3. Support for most non-compliant CSV variations (eg - @relax, @excel)
#
# TODO:
# 1. Support IO streaming
# 2. Add option to strip whitespace
# 3. Support CSV headers in first row
# ============================================================================

require "bundler/setup"
require "strscan"

class Censive < StringScanner

  def self.writer(obj=nil, **opts, &code)
    case obj
    when String then File.open(obj, "w") {|io| yield new(out: io, **opts, &code) }
    when IO,nil then new(out: obj, **opts, &code)
    else abort "#{File.basename($0)}: invalid #{obj.class} object in writer"
    end
  end

  def initialize(str=nil,
    drop:  false   , # drop trailing empty fields?
    eol:   "\n"    , # line endings for exports
    excel: false   , # literals ="01" formulas =A1 + B2 http://bit.ly/3Y7jIvc
    mode:  :compact, # export mode: compact or full
    out:   nil     , # output stream, needs to respond to <<
    quote: '"'     , # quote character
    relax: false   , # relax quote parsing so ,"Fo"o, => ,"Fo""o",
    sep:   ","     , # column separator character
    **opts           # grab bag
  )
    super(str || "")
    reset

    @drop   = drop
    @eol    = eol
    @excel  = excel
    @mode   = mode
    @out    = out || $stdout
    @quote  = quote
    @relax  = relax
    @sep    = sep

    @cr     = "\r"
    @lf     = "\n"
    @es     = ""
    @eq     = "="
    @esc    = (@quote * 2)
  end

  def reset(str=nil)
    self.string = str if str
    super()
    @char = curr_char
    @rows = nil
    @cols = @cells = 0
  end

  # ==[ Lexer ]==

  # pure ruby versions for debugging
  # def curr_char;             @char = string[pos]; end
  # def next_char; scan(/./m); @char = string[pos]; end

  def curr_char; @char = currchar; end
  def next_char; @char = nextchar; end

  def next_token
    if @excel && @char == @eq
      excel = true
      next_char
    end

    if @char == @quote # consume quoted cell
      token = ""
      while true
        next_char
        token << (scan_until(/(?=#{@quote})/o) or bomb "unclosed quote")
        token << @quote and next if next_char == @quote
        break if [@sep,@cr,@lf,@es,nil].include?(@char)
        @relax or bomb "invalid character after quote"
        token << @quote + scan_until(/(?=#{@quote})/o) + @quote
      end
      next_char if @char == @sep
      token
    elsif [@sep,@cr,@lf,@es,nil].include?(@char)
      case @char
      when @sep then next_char                     ; @es
      when @cr  then next_char == @lf and next_char; nil
      when @lf  then next_char                     ; nil
      else                                           nil
      end
    else # consume unquoted cell
      token = scan_until(/(?=#{@sep}|#{@cr}|#{@lf}|\z)/o) or bomb "unexpected character"
      token.prepend(@eq) if excel
      next_char if curr_char == @sep
      token
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
    if idx = str.index(/(#{@quote})|#{@sep}|#{@cr}|#{@lf}/o) #!# FIXME: regex injection?
      $1 ? 2 : str.index(/#{@quote}/o, idx) ? 2 : 1
    else
      0
    end
  end

  # output a row
  def <<(row)

    # drop trailing empty columns
    row.pop while row.last.empty? if @drop

    s,q = @sep, @quote
    out = case @mode
    when :compact
      case @excel ? 2 : grok(row.join)
      when 0
        row
      when 1
        row.map do |col|
          col.match?(/#{@sep}|#{@cr}|#{@lf}/o) ? "#{q}#{col}#{q}" : col
        end
      else
        row.map do |col|
          @excel && col =~ /\A0\d*\z/ ? "=#{q}#{col}#{q}" :
          case grok(col)
          when 0 then col
          when 1 then "#{q}#{col}#{q}"
          else        "#{q}#{col.gsub(q, @esc)}#{q}"
          end
        end
      end
    when :full
      if @excel
        row.map do |col|
          col =~ /\A0\d*\z/ ? "=#{q}#{col}#{q}" : "#{q}#{col.gsub(q, @esc)}#{q}"
        end
      else
        row.map {|col| "#{q}#{col.gsub(q, @esc)}#{q}" }
      end
    end.join(s)

    @out << out + @eol
  end

  def each
    @rows ||= parse
    @rows.each {|row| yield row }
  end

  def export(**opts)
    out = opts.empty? ? self : self.class.writer(**opts)
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
# raw = File.read(ARGV.first || "lc-2023.csv")
  csv = Censive.new(raw, excel: true, relax: true)
  csv.export # (sep: ",", excel: true)
end

__END__
Name,Age,Shoe
Alice,27,5
Bob,33,10 1/2
Charlie or "Chuck",=B2 + B3,9
"Doug E Fresh",="007",10
Subtotal,=sum(B2:B5),="01234"

# first line works in "relax" mode, bottom line is compliant
123,"CHO, JOELLE "JOJO"",456
123,"CHO, JOELLE ""JOJO""",456

# Excel mode checking
=,=x,x=,="x",="","","=",123,0123,="123",="0123"
,=x,x=,x,,,,,,=,,123,="0123",123,,="0123" # <= a little off
