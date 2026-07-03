--!optimize 2
const SQRT2 = math.sqrt(2)
const MAX15 = 32767

const function quantize(v: number): number
    return math.clamp(math.round((v * SQRT2 * 0.5 + 0.5) * MAX15), 0, MAX15)
end

const function dequantize(v: number): number
    return (v / MAX15 - 0.5) * 2 / SQRT2
end

const function cfToQuat(cf: CFrame): (number, number, number, number)
    local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    const trace = r00 + r11 + r22
    local qx, qy, qz, qw

    if trace > 0 then
        const s = 0.5 / math.sqrt(trace + 1)

        qw = 0.25 / s
        qx = (r21 - r12) * s
        qy = (r02 - r20) * s
        qz = (r10 - r01) * s
    elseif r00 > r11 and r00 > r22 then
        const s = 2 * math.sqrt(1 + r00 - r11 - r22)

        qw = (r21 - r12) / s
        qx = 0.25 * s
        qy = (r01 + r10) / s
        qz = (r02 + r20) / s
    elseif r11 > r22 then
        const s = 2 * math.sqrt(1 + r11 - r00 - r22)

        qw = (r02 - r20) / s
        qx = (r01 + r10) / s
        qy = 0.25 * s
        qz = (r12 + r21) / s
    else
        const s = 2 * math.sqrt(1 + r22 - r00 - r11)

        qw = (r10 - r01) / s
        qx = (r02 + r20) / s
        qy = (r12 + r21) / s
        qz = 0.25 * s
    end

    return qx, qy, qz, qw
end

const function writeRotation(self: any, cframe: CFrame): ()
    local rx, ry, rz, rw = cfToQuat(cframe)
    const vals = { rx, ry, rz, rw }

    local maxIdx, maxAbs = 1, 0
    for i = 1, 4 do
        const abs = math.abs(vals[i])
        if abs > maxAbs then
            maxIdx, maxAbs = i, abs
        end
    end

    const sign = if vals[maxIdx] < 0 then -1 else 1

    const others = {}
    for i = 1, 4 do
        if i ~= maxIdx then
            others[#others + 1] = vals[i] * sign
        end
    end

    const a = quantize(others[1])
    const b = quantize(others[2])
    const c = quantize(others[3])

    const idx = maxIdx - 1
    const hi = bit32.bor(bit32.lshift(idx, 30), bit32.lshift(a, 15), b)

    self:writeu32(hi)
    self:writeu16(c)
end

const function readRotation(self: any): (number, number, number, number)
    const hi = self:readu32()
    const c  = self:readu16()

    const idx = bit32.rshift(hi, 30)
    const a   = bit32.band(bit32.rshift(hi, 15), 0x7FFF)
    const b   = bit32.band(hi, 0x7FFF)

    local da, db, dc = dequantize(a), dequantize(b), dequantize(c)
    const dLargest = math.sqrt(math.max(0, 1 - da*da - db*db - dc*dc))

    const components = {}
    local oi, others = 1, { da, db, dc }
    for i = 0, 3 do
        if i == idx then
            components[i + 1] = dLargest
        else
            components[i + 1] = others[oi]
            oi += 1
        end
    end

    return components[1], components[2], components[3], components[4]
end

const CF = {}

function CF.read(self: any, posT: number, rotT: number): CFrame
    local x, y, z = 0, 0, 0
    if posT == 8 then
        x = self:readf64()
        y = self:readf64()
        z = self:readf64()
    elseif posT == 2 then
        x = self:readf16()
        y = self:readf16()
        z = self:readf16()
    else 
        x = self:readf32()
        y = self:readf32()
        z = self:readf32()
    end

    local rx, ry, rz, rw = 0, 0, 0, 0
    if rotT == 2 then
        rx, ry, rz, rw = readRotation(self)
    else 
        const read = rotT == 8 and self.readf64 or self.readf32

        rx = read(self)
        ry = read(self)
        rz = read(self)
        rw = read(self)
    end

    return CFrame.new(x, y, z, rx, ry, rz, rw)
end

function CF.write(self: any, posT: number, rotT: number, cframe: CFrame): ()
    if posT == 8 then
        self:writef64(cframe.X)
        self:writef64(cframe.Y)
        self:writef64(cframe.Z)
    elseif posT == 2 then
        self:writef16(cframe.X)
        self:writef16(cframe.Y)
        self:writef16(cframe.Z)
    else 
        self:writef32(cframe.X)
        self:writef32(cframe.Y)
        self:writef32(cframe.Z)
    end
    
    if rotT == 2 then
        writeRotation(self, cframe)
    else 
        local rx, ry, rz, rw = cfToQuat(cframe)
        const write = rotT == 8 and self.writef64 or self.writef32
        
        write(self, rx)
        write(self, ry)
        write(self, rz)
        write(self, rw)
    end
end

return CF