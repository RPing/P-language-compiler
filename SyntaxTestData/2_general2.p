/**
 * general2.p: general case 2
 */
//&T-
general1;

var a: integer;
var b, c: array 1 to 5 of real;

func12345678901234567890( e, f: array 1 to 5 of real ): array 1 to 5 of real;
begin
        var i: integer;
        var result: array 1 to 5 of real;
        i := 1;
        while i <= 5 do
                result[i] := e[i]*f[i];
        end do

        return result;
end
end func2

begin
        var ii : integer;
        var r : array 3 to 7 of real;

        r := func12345678901234567890( b, c );
end
end general1
