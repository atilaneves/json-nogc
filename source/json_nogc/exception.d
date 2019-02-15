module json_nogc.exception;


import localimport;


class ConvException: from.nogc.NoGcException {
    import nogc: NoGcExceptionCtors;
    mixin NoGcExceptionCtors;
}
