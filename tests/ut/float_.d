module ut.float_;


import ut;


@("float")
@safe @nogc unittest {
    auto str = "3.3";
    assert(str.parse!float == 3.3f);
}


@("double")
@safe @nogc unittest {
    auto str = "3.3";
    assert(str.parse!double == 3.3);
}
