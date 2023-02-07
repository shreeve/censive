#!/usr/bin/env ruby

# ============================================================================
# censive - A quick and lightweight CSV handling library for Ruby
#
# Author: Steve Shreeve (steve.shreeve@gmail.com)
#   Date: Feb 6, 2023
#
# https://crystal-lang.org/api/1.7.2/CSV.html (Crystal's CSV library)
# https://github.com/ruby/strscan/blob/master/ext/strscan/strscan.c
#
# Thanks to Sutou Kouhei (kou) for his excellent advice on using scan
# ============================================================================
# GOALS:
# 1. Faster than Ruby's default CSV library
# 2. Lightweight code with streamlined and optimized logic
# 3. Support most non-compliant CSV variations (eg - @excel, @relax, @strip)
#
# TODO:
# 1. Support IO streaming
# 2. Review all encodings, we may be losing speed when mixing encodings
# 3. Huge speedup possible if our @unquoted regex reads beyond @cr?@lf's
# 4. Will using String#freeze give us a speed up?
# 5. Implement support for scan_until(string) <= right now only regex is valid
# ============================================================================

require "strscan"

class Censive < StringScanner
  def self.parse(...)
    new(...).parse
  end

  def self.writer(obj=nil, **opts, &code)
    case obj
    when String then File.open(obj, "w") {|io| yield new(out: io, **opts, &code) }
    when IO,nil then new(out: obj, **opts, &code)
    else abort "#{File.basename($0)}: invalid #{obj.class} object in writer"
    end
  end

  def initialize(str=nil,
    drop:     false   , # drop trailing empty fields?
    encoding: nil     , # character encoding
    excel:    false   , # literals ="01" formulas =A1 + B2 http://bit.ly/3Y7jIvc
    mode:     :compact, # export mode: compact or full
    out:      nil     , # output stream, needs to respond to <<
    quote:    '"'     , # quote character
    relax:    false   , # relax quote parsing so ,"Fo"o, => ,"Fo""o",
    rowsep:   "\n"    , # row separator for export
    sep:      ","     , # column separator character
    strip:    false   , # strip fields when reading
    **opts              # grab bag
  )
    # initialize data source
    if str && str.size < 100 && File.readable?(str)
      str = File.open(str, encoding ? "r:#{encoding}" : "r").read
    else
      str ||= ""
      str = str.encode(encoding) if encoding
    end
    super(str)
    reset

    # config options
    @drop     = drop
    @encoding = str.encoding
    @excel    = excel
    @mode     = mode
    @out      = out || $stdout
    @relax    = relax
    @strip    = strip

    # config strings
    @quote    = quote
    @rowsep   = rowsep
    @sep      = sep

    # static strings
    @cr       = "\r"
    @lf       = "\n"
    @es       = ""
    @eq       = "="

    # combinations
    @esc      = (@quote * 2)
    @eqq      = [@eq , @quote].join # used for parsing in excel mode
    @seq      = [@sep, @eq   ].join # used for parsing in excel mode

    # regexes
    @eoc      = /(?=#{"\\" + @sep}|#{@cr}|#{@lf}|\z)/o # end of cell
    @eol      = /#{@cr}#{@lf}?|#{@lf}|\z/o             # end of line
    @escapes  = /(#{@quote})|#{"\\"+@sep}|#{@cr}|#{@lf}/o
    @quotable = /#{"\\"+@sep}|#{@cr}|#{@lf}/o
    @quotes   = /#{@quote}/o
    @seps     = /#{@sep}+/o
    @unquoted = /[^#{@quote}#{@sep}#{@cr}#{@lf}][^#{@quote}#{@cr}#{@lf}]*/o
    @leadzero = /\A0\d*\z/

  # # setup row parser
  # @row_parser = row_parser
  end

  def reset(str=nil)
    self.string = str if str
    super()
    @rows = nil
    @cols = @cells = 0
  end

  # ==[ Lexer ]==

  def next_token
    if match = scan(@unquoted) # unquoted cell(s)
      if check(@quote) && !match.chomp!(@sep) # no sep before final quote
        if @excel && !match.chomp!(@seq) # excel mode allows sep, eq, quote
          match << (scan_until(@eoc) or bomb "unexpected character")
          scan(@sep)
        end
      end
      tokens = match.split(@sep, -1)
      @strip ? tokens.map!(&:strip) : tokens
    elsif scan(@quote) || (@excel && (excel = scan(@eqq))) # quoted cell
      token = ""
      while true
        token << (scan_until(@quotes) or bomb "unclosed quote")[0..-2]
        token << @quote and next if scan(@quote)
        scan(@eoc) and break
        @relax or bomb "invalid character after quote"
        token << @quote + (scan_until(@quotes) or bomb "bad inline quote")
      end
      scan(@sep)
      @strip ? token.strip : token
    elsif scan(@sep)
      match = scan(@seps)
      match ? match.split(@sep, -1) : @es
    else
      scan(@eol)
      nil
    end
  end

  def bomb(msg)
    abort "\n#{File.basename($0)}: #{msg} at character #{pos} near '#{string[pos-4,7]}'"
  end

  # ==[ Parser ]==

  def parse
    @rows = []
  # while row = @row_parser.next
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
    row = []
    row.push(*token)
    row.push(*token) while token = next_token
    row
  end

# def row_parser
#   Enumerator.new do |yielder|
#     loop do
#       tokens = next_token or yielder.yield
#       row = []
#       row.push(*tokens)
#       row.push(*tokens) while tokens = next_token
#       yielder.yield row
#     end
#   end
# end

  def each
    @rows ||= parse
    @rows.each {|row| yield row }
  end

  def export(**opts)
    out = opts.empty? ? self : self.class.writer(**opts)
    each {|row| out << row }
  end

  # ==[ Helpers ]==

  # returns 2 (must be quoted and escaped), 1 (must be quoted), 0 (neither)
  def grok(str)
    if idx = str.index(@escapes)
      $1 ? 2 : str.index(@quotes, idx) ? 2 : 1
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
          col.match?(@quotable) ? "#{q}#{col}#{q}" : col
        end
      else
        row.map do |col|
          @excel && col =~ @leadzero ? "=#{q}#{col}#{q}" :
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
          col =~ @leadzero ? "=#{q}#{col}#{q}" : "#{q}#{col.gsub(q, @esc)}#{q}"
        end
      else
        row.map {|col| "#{q}#{col.gsub(q, @esc)}#{q}" }
      end
    end.join(s)

    @out << out + @rowsep
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
  csv.export(excel: true, sep: "|")
end

__END__
Name,Age,Shoe
Alice,27,5
Bob,33,10 1/2
Charlie or "Chuck",=B2 + B3,9
"Doug E Fresh",="007",10
Subtotal,=sum(B2:B5),="01234"

A,B,C,D
A,B,"C",D
A,B,C",D
A,B,"C",D

# first line works in "relax" mode, bottom line is compliant
123,"CHO, JOELLE "JOJO"",456
123,"CHO, JOELLE ""JOJO""",456

# Excel mode checking
=,=x,x=,="x",="","","=",123,0123,="123",="0123"
,=x,x=,x,,,,,,=,,123,="0123",123,,="0123" # <= a little off
