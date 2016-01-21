//&T-
demo;
Chu():integer;
begin
    return 381;
end
end Chu

Tsai():integer;
begin
    return 689;
end
end Tsai

Soong():integer;
begin
    return 157;
end
end Soong

begin
    var i, j: integer;
    var b: boolean;

    b := true;
    while b do
        print "1:Chu 2:Tsai 3:Soong   0:exit\n"
            + "which candidate you want to know?\n";
        read j;
        if j = 0 then
            b := false;
        else
            if j = 1 then
                i := Chu();
                print "Chu: ";
                print i;
                print "\n";
            else
                if j = 2 then
                    i := Tsai();
                    print "Tsai: ";
                    print i;
                    print " President!";
                    print "\n";
                else
                    if j = 3 then
                        i := Soong();
                        print "Soong: ";
                        print i;
                        print "\n";
                    end if
                end if
            end if
        end if
    end do
end

end demo
