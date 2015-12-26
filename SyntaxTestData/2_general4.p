/**
 * general4.p: general case 4
 */
//&T-

general4;

recursive( index: integer ): integer;
begin
        if ( index = 1 ) then  
                return 1;
        else
                return recursive( index-1 )+index;
        end if
end 
end recursive

begin
        var a : integer;
        read a;
        print recursive(a);
end 
end general4
