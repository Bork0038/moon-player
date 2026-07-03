--!optimize 2
const function EQ(a: any, b: any): boolean
    const t = typeof(a)
    
    if t ~= typeof(b) then
        return false
    end 

    if t == "CFrame" then
        return a.Position == b.Position and a.Rotation == b.Rotation
    elseif t == "ColorSequence" then
        if #a.Keypoints ~= #b.Keypoints then 
            return false 
        end

        for i, kp in a.Keypoints do
            const bkp = b.Keypoints[i]

            if kp.Time ~= bkp.Time or kp.Value ~= bkp.Value then 
                return false 
            end
        end

        return true
    elseif t == "NumberSequence" then
        if #a.Keypoints ~= #b.Keypoints then 
            return false
        end

        for i, kp in a.Keypoints do
            const bkp = b.Keypoints[i]

            if kp.Time ~= bkp.Time or kp.Value ~= bkp.Value or kp.Envelope ~= bkp.Envelope then 
                return false 
            end
        end
        
        return true
    end
    return a == b
end

return EQ