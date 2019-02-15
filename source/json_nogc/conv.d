module json_nogc.conv;


import localimport;


/**
   Copied from Phobos but made to be @nogc
 */
Target parse(Target, Source)(ref Source source)
    if (from.std.range.primitives.isInputRange!Source &&
        std.traits.isSomeChar!(std.range.primitives.ElementType!Source) &&
        !is(Source == enum) &&
        std.traits.isFloatingPoint!Target &&
        !is(Target == enum))
{
    import std.ascii : isDigit, isAlpha, toLower, toUpper, isHexDigit;
    import std.array: empty, front, popFront;
    import std.conv: text;
    import std.traits: isNarrowString;

    static if (isNarrowString!Source)
    {
        import std.string : representation;
        auto p = source.representation;
    }
    else
    {
        alias p = source;
    }

    static immutable real[14] negtab =
        [ 1e-4096L,1e-2048L,1e-1024L,1e-512L,1e-256L,1e-128L,1e-64L,1e-32L,
                1e-16L,1e-8L,1e-4L,1e-2L,1e-1L,1.0L ];
    static immutable real[13] postab =
        [ 1e+4096L,1e+2048L,1e+1024L,1e+512L,1e+256L,1e+128L,1e+64L,1e+32L,
                1e+16L,1e+8L,1e+4L,1e+2L,1e+1L ];

    void enforce(in bool cond, string msg = "Floating point conversion error", in string file = __FILE__, in size_t line = __LINE__) @safe {
        import json_nogc.exception: ConvException;
        import nogc.exception: File, Line;

        if(!cond)
            ConvException.throw_(File(file), Line(line), msg, ` for input "`, source, `".`);
    }


    enforce(!p.empty);

    bool sign = false;
    switch (p.front)
    {
    case '-':
        sign = true;
        p.popFront();
        enforce(!p.empty);
        if (toLower(p.front) == 'i')
            goto case 'i';
        break;
    case '+':
        p.popFront();
        enforce(!p.empty);
        break;
    case 'i': case 'I':
        // inf
        p.popFront();
        enforce(!p.empty && toUpper(p.front) == 'N',
               "error converting input to floating point");
        p.popFront();
        enforce(!p.empty && toUpper(p.front) == 'F',
               "error converting input to floating point");
        // skip past the last 'f'
        p.popFront();
        static if (isNarrowString!Source)
            source = cast(Source) p;
        return sign ? -Target.infinity : Target.infinity;
    default: {}
    }

    bool isHex = false;
    bool startsWithZero = p.front == '0';
    if (startsWithZero)
    {
        p.popFront();
        if (p.empty)
        {
            static if (isNarrowString!Source)
                source = cast(Source) p;
            return sign ? -0.0 : 0.0;
        }

        isHex = p.front == 'x' || p.front == 'X';
        if (isHex) p.popFront();
    }
    else if (toLower(p.front) == 'n')
    {
        // nan
        p.popFront();
        enforce(!p.empty && toUpper(p.front) == 'A',
               "error converting input to floating point");
        p.popFront();
        enforce(!p.empty && toUpper(p.front) == 'N',
               "error converting input to floating point");
        // skip past the last 'n'
        p.popFront();
        static if (isNarrowString!Source)
            source = cast(Source) p;
        return typeof(return).nan;
    }

    /*
     * The following algorithm consists of 2 steps:
     * 1) parseDigits processes the textual input into msdec and possibly
     *    lsdec/msscale variables, followed by the exponent parser which sets
     *    exp below.
     *    Hex: input is 0xaaaaa...p+000... where aaaa is the mantissa in hex
     *    and 000 is the exponent in decimal format with base 2.
     *    Decimal: input is 0.00333...p+000... where 0.0033 is the mantissa
     *    in decimal and 000 is the exponent in decimal format with base 10.
     * 2) Convert msdec/lsdec and exp into native real format
     */

    real ldval = 0.0;
    char dot = 0;                        /* if decimal point has been seen */
    int exp = 0;
    ulong msdec = 0, lsdec = 0;
    ulong msscale = 1;
    bool sawDigits;

    enum { hex, decimal }

    // sets msdec, lsdec/msscale, and sawDigits by parsing the mantissa digits
    void parseDigits(alias FloatFormat)()
    {
        static if (FloatFormat == hex)
        {
            enum uint base = 16;
            enum ulong msscaleMax = 0x1000_0000_0000_0000UL; // largest power of 16 a ulong holds
            enum ubyte expIter = 4; // iterate the base-2 exponent by 4 for every hex digit
            alias checkDigit = isHexDigit;
            /*
             * convert letter to binary representation: First clear bit
             * to convert lower space chars to upperspace, then -('A'-10)
             * converts letter A to 10, letter B to 11, ...
             */
            alias convertDigit = (int x) => isAlpha(x) ? ((x & ~0x20) - ('A' - 10)) : x - '0';
            sawDigits = false;
        }
        else static if (FloatFormat == decimal)
        {
            enum uint base = 10;
            enum ulong msscaleMax = 10_000_000_000_000_000_000UL; // largest power of 10 a ulong holds
            enum ubyte expIter = 1; // iterate the base-10 exponent once for every decimal digit
            alias checkDigit = isDigit;
            alias convertDigit = (int x) => x - '0';
            // Used to enforce that any mantissa digits are present
            sawDigits = startsWithZero;
        }
        else
            static assert(false, "Unrecognized floating-point format used.");

        while (!p.empty)
        {
            int i = p.front;
            while (checkDigit(i))
            {
                sawDigits = true;        /* must have at least 1 digit   */

                i = convertDigit(i);

                if (msdec < (ulong.max - base)/base)
                {
                    // For base 16: Y = ... + y3*16^3 + y2*16^2 + y1*16^1 + y0*16^0
                    msdec = msdec * base + i;
                }
                else if (msscale < msscaleMax)
                {
                    lsdec = lsdec * base + i;
                    msscale *= base;
                }
                else
                {
                    exp += expIter;
                }
                exp -= dot;
                p.popFront();
                if (p.empty)
                    break;
                i = p.front;
                if (i == '_')
                {
                    p.popFront();
                    if (p.empty)
                        break;
                    i = p.front;
                }
            }
            if (i == '.' && !dot)
            {
                p.popFront();
                dot += expIter;
            }
            else
                break;
        }

        // Have we seen any mantissa digits so far?
        enforce(sawDigits, "no digits seen");
        static if (FloatFormat == hex)
            enforce(!p.empty && (p.front == 'p' || p.front == 'P'),
                    "Floating point parsing: exponent is required");
    }

    if (isHex)
        parseDigits!hex;
    else
        parseDigits!decimal;

    if (isHex || (!p.empty && (p.front == 'e' || p.front == 'E')))
    {
        char sexp = 0;
        int e = 0;

        p.popFront();
        enforce(!p.empty, "Unexpected end of input");
        switch (p.front)
        {
            case '-':    sexp++;
                         goto case;
            case '+':    p.popFront();
                         break;
            default: {}
        }
        sawDigits = false;
        while (!p.empty && isDigit(p.front))
        {
            if (e < 0x7FFFFFFF / 10 - 10)   // prevent integer overflow
            {
                e = e * 10 + p.front - '0';
            }
            p.popFront();
            sawDigits = true;
        }
        exp += (sexp) ? -e : e;
        enforce(sawDigits, "No digits seen.");
    }

    ldval = msdec;
    if (msscale != 1)               /* if stuff was accumulated in lsdec */
        ldval = ldval * msscale + lsdec;
    if (isHex)
    {
        import std.math : ldexp;

        // Exponent is power of 2, not power of 10
        ldval = ldexp(ldval,exp);
    }
    else if (ldval)
    {
        uint u = 0;
        int pow = 4096;

        while (exp > 0)
        {
            while (exp >= pow)
            {
                ldval *= postab[u];
                exp -= pow;
            }
            pow >>= 1;
            u++;
        }
        while (exp < 0)
        {
            while (exp <= -pow)
            {
                ldval *= negtab[u];
                enforce(ldval != 0, "Range error");
                exp += pow;
            }
            pow >>= 1;
            u++;
        }
    }

    // if overflow occurred
    enforce(ldval != real.infinity, "Range error");

    static if (isNarrowString!Source)
        source = cast(Source) p;
    return sign ? -ldval : ldval;
}
