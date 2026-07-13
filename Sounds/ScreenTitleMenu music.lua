local audio_file = "_silent"

if ThemePrefs.Get("TitleMenuMusic") == "Moomin" then
	audio_file = "menu_music_moomin.ogg"
end

return THEME:GetPathS("", audio_file)
