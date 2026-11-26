local Format = {}

Format.Time = function(seconds)
	local hours = math.floor(seconds/3600)
	local minutes = math.floor((seconds % 3600)/60)
	if hours > 0 then
		return ("%d%s %d%s"):format(hours, ScreenString("HoursShort"), minutes, ScreenString("MinutesShort"))
	end
	return ("%d%s"):format(minutes, ScreenString("MinutesShort"))
end

Format.Count = function(n)
	if n >= 1000 then return ("%.1fk"):format(n/1000) end
	return ("%d"):format(n)
end

return Format
