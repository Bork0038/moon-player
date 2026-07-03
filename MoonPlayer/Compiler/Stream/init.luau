--!optimize 2
const LogService = game:GetService("LogService")

const BUFFER_SIZE = 65535;

const INF = math.huge
const LOG2 = math.log(2)
const DENORM_SCALE = 5.960464477539063e-08

const floor = math.floor
const log = math.log

const CF = require("@self/CFrame")

const Stream = {
    writeCFrame = CF.write,
    readCFrame = CF.read
};

function Stream.new(buf: (buffer | string)?, allocationSize: number?)
	if typeof(buf) == "string" then
		buf = buffer.fromstring(buf);
	end

	const len = buf and buffer.len(buf :: buffer) or 0;
	buf = buf or buffer.create(allocationSize or BUFFER_SIZE);

	return setmetatable(
		{
			buf = buf,
			capacity = buffer.len(buf :: buffer),
			read = 0,
			write = 0,
			size = len,
			alloc_size = allocationSize or BUFFER_SIZE,
			markers = {}
		},
		{ __index = Stream }
	);
end

function Stream:addBytesAndReallocate(bytes: number): ()
	const size = buffer.len(self.buf);
	const newBuf = buffer.create(size + bytes);

	buffer.copy(newBuf, 0, self.buf, 0, size);
	self.buf = newBuf;
	self.capacity = size + bytes;
end

function Stream:appendStream(other: any): ()	
	self:writebytes(other:tobuffer())
end

function Stream:writebytes(buf: buffer): ()
	const len = buffer.len(buf)

	if self.write + len > self.capacity - 1 then
		self:addBytesAndReallocate(len + 1);
	end

	buffer.copy(self.buf, self.write, buf, 0)
	
	if self.write == self.size then
		self.size  += len;
	end
	self.write += len;
end

function Stream:len(): number
	return self.size;
end

const sizet = { 1, 2, 4 };
for index, size in sizet do
	const bits = size * 8;

	const u = "u" .. bits;
	const i = "i" .. bits;

	const wun = "write" .. u;
	const win = "write" .. i;

	const wuf = buffer[wun];
	const wif = buffer[win];

	Stream[wun] = function(self: any, num: number): ()
		if self.write + size > self.capacity - 1 then
			self:addBytesAndReallocate(self.alloc_size);
		end

		wuf(self.buf, self.write, num);
		
		if self.write == self.size then
			self.size  += size;
		end
		self.write += size;
	end

	Stream[win] = function(self: any, num: number): ()
		if self.write + size > self.capacity - 1 then
			self:addBytesAndReallocate(self.alloc_size);
		end

		wif(self.buf, self.write, num);
		
		if self.write == self.size then
			self.size  += size;
		end
		self.write += size;
	end

	const run = "read" .. u;
	const rin = "read" .. i;

	const ruf = buffer[run];
	const rif = buffer[rin];

	Stream[run] = function(self: any, num: number?): number
		if self.read + size > self.size then
			LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
		end

		const int = ruf(self.buf, self.read);
		self.read += size;

		return int;
	end

	Stream[rin] = function(self: any, num: number?): number
		if self.read + size > self.size then
			LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
		end

		const int = rif(self.buf, self.read);
		self.read += size;

		return int;
	end
end

function Stream:createMarker(name: string, size: number): ()
	const pos = self.write
	const buf = buffer.create(size)
	
	self:writebytes(buf)
	self.markers[name] = pos
end

function Stream:seekMarker(name: string)
	const pos = self.markers[name]
	
	if not pos then
		return LogService:Warn("[MoonPlayer/Compiler/Stream]: no pos found for marker {name}", {name = name})
	end
	
	self.write = pos

	return nil
end

function Stream:clearMarkers(): ()
	self.markers = {}
end

function Stream:resume(): ()
	self.write = self.size
end

function Stream:writebool(bool: boolean): ()
	self:writeu8(bool and 0x01 or 0x00);
end

function Stream:readbool(): boolean
	return self:readu8() == 0x01;
end

function Stream:writeu64(num: number): ()
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writestring(
		self.buf,
		self.write,
		string.pack("<I8", num),
		8
	);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:readu64(): number
	if self.read + 8 > self.size then
		LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
	end

	const str = buffer.readstring(self.buf, self.read, 8);
	self.read += 8;

	const num = string.unpack("<I8", str);
	return num;
end

function Stream:writei64(num: number): ()
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writestring(
		self.buf,
		self.write,
		string.pack("<i8", num),
		8
	);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:readi64(): number
	if self.read + 8 > self.size then
		LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
	end

	const str = buffer.readstring(self.buf, self.read, 8);
	self.read += 8;

	const num = string.unpack("<i8", str);
	return num;
end

function Stream:readf32(): number
	if self.read + 4 > self.size then
		LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
	end

	const int = buffer.readf32(self.buf, self.read);
	self.read += 4;

	return int;
end

function Stream:readf64(): number
	if self.read + 8 > self.size then
		LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size});
	end

	const int = buffer.readf64(self.buf, self.read);
	self.read += 8;

	return int;
end

function Stream:writef32(f: number): ()
	if self.write + 4 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writef32(self.buf, self.write, f);
	
	if self.write == self.size then
		self.size  += 4;
	end
	self.write += 4;
end

function Stream:writef64(f: number): ()
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writef64(self.buf, self.write, f);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:writestring(str: string, sizeT: number?): ()
	const trueSizeT = sizeT or 32 :: number;

	const len = str:len();
	if self.write + (trueSizeT / 8) + len > self.capacity - 1 then
		self:addBytesAndReallocate(math.max(
			self.alloc_size, 
			(trueSizeT / 8) + len
		))
	end

	self["writeu" .. trueSizeT](self, len);
	buffer.writestring(self.buf, self.write, str, len);
	
	if self.write == self.size then
		self.size  += len;
	end
	self.write += len;
end

function Stream:readstring(sizeT: number?): string
	const trueSizeT = sizeT or 32 :: number;

	const len = self["readu" .. trueSizeT](self);
	const str = buffer.readstring(self.buf, self.read, len);
	self.read += len;

	return str;
end

function Stream:writevector3(vec: Vector3): ()
	self:writef32(vec.X);
	self:writef32(vec.Y);
	self:writef32(vec.Z);
end

function Stream:readvector3(): Vector3
	return Vector3.new(
		self:readf32(),
		self:readf32(),
		self:readf32()
	)
end

function Stream:tobuffer(): buffer
	const buf = buffer.create(self.size);
	buffer.copy(buf, 0, self.buf, 0, self.size);

	return buf;
end

function Stream:tostring(): string
	return buffer.tostring(self:tobuffer())
end

function Stream:writef16(n: number): ()
    if self.write + 2 > self.capacity - 1 then
        self:addBytesAndReallocate(self.alloc_size)
    end

    const bitOffset = self.write * 8

    local sign = 0
    if n < 0 then
        sign = 1
        n = -n
    end

    local bits

    if n == INF then
        bits = bit32.lshift(sign, 15) + bit32.lshift(0x1F, 10)

    elseif n ~= n then
        bits = bit32.lshift(sign, 15) + bit32.lshift(0x1F, 10) + 1

    elseif n < 6.10352e-05 then
        const mantissa = floor(n / DENORM_SCALE + 0.5)
        bits = bit32.lshift(sign, 15) + mantissa

    elseif n > 65504 then
        bits = bit32.lshift(sign, 15) + bit32.lshift(0x1F, 10)

    else
        const exponent = floor(log(n) / LOG2)
        const mantissa = floor((n / (2 ^ exponent) - 1) * 1024 + 0.5)
        const exponentBits = exponent + 15

        bits = bit32.lshift(sign, 15)
            + bit32.lshift(exponentBits, 10)
            + mantissa
    end

    buffer.writebits(self.buf, bitOffset, 16, bits)

    if self.write == self.size then
        self.size += 2
    end
    self.write += 2
end

function Stream:readf16(): number
    if self.read + 2 > self.size then
        LogService:Error("[MoonPlayer/Compiler/Stream]: attempt to read out of bounds at {read} (size {size})", {read = self.read, size = self.size})
    end

    const bitOffset = self.read * 8
    const bits = buffer.readbits(self.buf, bitOffset, 16)
    self.read += 2

    const sign = bit32.rshift(bits, 15) == 1
    const signMult = sign and -1 or 1

    const exponent = bit32.band(bit32.rshift(bits, 10), 0x1F)
    const mantissa = bit32.band(bits, 0x3FF)

    if exponent == 0 then
        if mantissa == 0 then
            return 0 * signMult
        else
            return signMult * mantissa * DENORM_SCALE
        end

    elseif exponent == 0x1F then
        if mantissa ~= 0 then
            return 0/0
        else
            return sign and -INF or INF
        end
    end

    return signMult * (1 + mantissa / 1024) * (2 ^ (exponent - 15))
end

return Stream