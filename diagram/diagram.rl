%%{
    machine csv;

    variable p s->p;
    variable pe s->pe;
    variable eof s->eof;
    access s->;

    eol = [\r\n];
    comment = '#';
    CR = "\r";
    LF = "\n";

    EOF = 0;
    EOL = /\r?\n/;
    comma = [,];
    string = [^,"\r\n\0]*;
    quote = '"' [^"\0]* '"';

    csv_scan := |*

    string => {
        return_token(TK_String);
        fbreak;
    };

    quote => {
        return_token(TK_Quote);
        s->data += 1;
        fbreak;
    };

    comma => {
        return_token(TK_Comma);
        fbreak;
    };

    EOL => {
        s->curline += 1;
        return_token(TK_EOL);
        fbreak;
    };

    EOF => {
        return_token(TK_EOF);
        fbreak;
    };

    *|;
}%%
