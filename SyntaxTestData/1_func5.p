/*
 * Function_5
 *
 */
//&T-
func5;

var a : integer;

fun(): array 1 to 5 of integer;   // return 1D size=5 integer array
begin
    var tmp : array 1 to 5 of integer;
    return tmp;
end
end fun

fun2(): array 1 to 5 of array 1 to 10 of integer;  // return 2D 5x10 integer array 
begin
    var tmp : array 1 to 5 of array 1 to 10 of integer;
    return tmp;
end
end fun2

fun3(): array 1 to 5 of array 1 to 5 of boolean;  // return 2D 5x5 boolean array 
begin
    var tmp : array 1 to 5 of array 1 to 5 of boolean;
    return tmp;
end
end fun3

begin
    var d : integer;
end
end func5

