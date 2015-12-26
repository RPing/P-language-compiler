/**
 * simplestmterror.p: about assignment
 */
//&T-

simplestmterror;

func():integer;
begin
        return 321;
end
end func

begin
        func() := 123;          // LHS of assignment cannot be the result of funcion invocation
end
end simplestmterror

