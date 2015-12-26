/**
 * mix3.p: mixed expression(s)
 */

//&T-

mix3;

begin

        var x1, y1: real;
        var x2, y2: real;
        var dist: real;

        var e :boolean;

        x1 := (1+2*3+(4*5+6*7)+(8*9+10))*1.1;
        x2 := 108 mod 22;
        y1 := 911;
        y2 := 123E-2 *18.5;

        e := x1 < x2;
        e := y1 >= y2;

        dist := (x2-x1)*(x2-x1)+(y2-y1)*(y2-y1);
end
end mix3
