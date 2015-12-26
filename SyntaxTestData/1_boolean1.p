/**
 * boolean1.p: and or (binary operator)
 */

//&T-

boolean1;

begin
        var a, b: boolean;
        var c: boolean;

        a := true;
        b := false;

        c := a and b;
        c := b and false;
        c := a or true;
        c := a and b or true and false;
end
end boolean1
