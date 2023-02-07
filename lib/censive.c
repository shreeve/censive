

    @unquoted = /[^#{@quote}#{@sep}#{@cr}#{@lf}][^#{@quote}#{@cr}#{@lf}]*/o


// make sure str has at least one ascii 0 after it "abc\0\0"

while (c) {
  if ((c != '"') && (c != ',') && (c != "\r") && (c != "\n")) { // unquoted
  } else if ((c == '"') || (_x && ((c == '=') || (c2 == '"')))) { // quoted
  } else if ((c == ",")) { // sep
  } else {
    if       (c == "\n")                  { p += 1; }
    else if ((c == "\r") && (c2 == "\n")) { p += 2; }
    return; // end of line
  }
}
