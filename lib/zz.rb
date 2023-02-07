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


  def next_row
    token = next_token or return
    row = []
    row.push(*token)
    row.push(*token) while token = next_token
    row
  end

