/**
 * boolean3.p: and or not
 */
//&T-

boolean3;

begin
        var a, b: boolean;
        var c: boolean;

        a := true;
        b := false;

        c := not a and b;
        c := not b and false;
        c := a or true;
        c := a and ( not b ) or true and (not false);
end
end boolean3
