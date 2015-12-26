/**
 * general5.p: general case 5
 */
//&T-

general5;

var sptr: integer;
var data: array 0 to 99 of string;
var sizeStack: 100;

init();
begin
        sptr := -1;
end
end init

push( item: string );
begin
        sptr := sptr+1;
        data[sptr] := item;
end
end push

top():string;
begin
        return data[sptr];
end
end top

pop():string;
begin
        sptr := sptr-1;
        return data[sptr+1];
end
end pop

isEmpty(): boolean;
begin
        return sptr = -1;
end
end isEmpty

isFull(): boolean;
begin
        return (sptr = (sizeStack-1));
end
end isFull

begin
        init();
        push("hello");
        push(" P language");
        push("\n");

        while not isEmpty() do
                print pop();
        end do
end 
end general5
