/**
 * parentheses2.p: advanced parentheses
 */

//&T-

parentheses2;

begin
        var a, b: integer;
        
        a := 1+(2*(3+4));
        a := ((1+2)*3-4);
        a := ((1+2)*(3-4));
        a := (((1+3)*(12+34))/(49/7));
        a := b+(a)*(31-8);
        a := (a+b)*(1);
        b := ((((((((((1))))))))));
        b := (((((((a+1)))))*(23 mod 3)));
end
end parentheses2
