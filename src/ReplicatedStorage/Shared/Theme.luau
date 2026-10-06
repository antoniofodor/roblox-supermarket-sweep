-- Every colour and font in the game. Grounds are neutral paper; colour goes on
-- objects and states. Every card gets a hard ink outline.

local Theme = {}

-- UI
Theme.INK = Color3.fromRGB(34, 30, 38)
Theme.PAPER = Color3.fromRGB(255, 250, 238)
Theme.PAPER_DEEP = Color3.fromRGB(238, 230, 212)
Theme.MUTED = Color3.fromRGB(104, 96, 92)

Theme.GOOD = Color3.fromRGB(70, 176, 98)
Theme.WARN = Color3.fromRGB(246, 178, 44)
Theme.STOP = Color3.fromRGB(224, 66, 54)
Theme.GOLD = Color3.fromRGB(242, 192, 44)
Theme.COOL = Color3.fromRGB(72, 142, 230)
Theme.LOVE = Color3.fromRGB(232, 92, 150)
Theme.CHONK = Color3.fromRGB(150, 90, 210) -- everything Big Chonk says

-- Text forms of the accents, dark enough to read on paper.
Theme.GOOD_INK = Color3.fromRGB(30, 112, 58)
Theme.WARN_INK = Color3.fromRGB(150, 90, 0)
Theme.STOP_INK = Color3.fromRGB(176, 38, 28)
Theme.GOLD_INK = Color3.fromRGB(140, 100, 0)
Theme.LOVE_INK = Color3.fromRGB(170, 40, 100)
Theme.CHONK_INK = Color3.fromRGB(100, 50, 160)

Theme.DISPLAY = Enum.Font.FredokaOne
Theme.BODY = Enum.Font.GothamBold
Theme.BODY_LIGHT = Enum.Font.GothamMedium

Theme.CORNER = 12
Theme.OUTLINE = 3

-- Announcement kinds: stripe colour per kind.
Theme.KIND = {
	go = Theme.GOOD,
	good = Theme.GOOD,
	info = Theme.COOL,
	warn = Theme.WARN,
	urgent = Theme.STOP,
	bad = Theme.STOP,
	note = Theme.MUTED,
	chonk = Theme.CHONK,
}

-- Big Chonk's mood meter: the three zones, and their text forms.
Theme.MOOD = {
	angry = { fill = Theme.STOP, ink = Theme.STOP_INK, word = "ANGRY" },
	content = { fill = Theme.WARN, ink = Theme.WARN_INK, word = "CONTENT" },
	love = { fill = Theme.LOVE, ink = Theme.LOVE_INK, word = "LOVE" },
}

-- World (the store build)
Theme.WORLD = {
	ground = Color3.fromRGB(122, 176, 90),
	lobby = Color3.fromRGB(198, 192, 180),
	floor = Color3.fromRGB(240, 236, 226),
	wall = Color3.fromRGB(250, 246, 236),
	trim = Color3.fromRGB(226, 72, 60),
	shelf = Color3.fromRGB(92, 140, 196),
	ledge = Color3.fromRGB(64, 104, 156),
	fridge = Color3.fromRGB(214, 234, 246),
	fridgeLedge = Color3.fromRGB(150, 182, 204),
	produce = Color3.fromRGB(150, 108, 68),
	counter = Color3.fromRGB(226, 72, 60),
	register = Color3.fromRGB(60, 60, 72),
	pad = Color3.fromRGB(124, 214, 124),
	padBusy = Color3.fromRGB(246, 196, 64),
	shutter = Color3.fromRGB(150, 156, 166),
	glass = Color3.fromRGB(170, 214, 240),
	exitDoor = Color3.fromRGB(214, 70, 58),
	sign = Color3.fromRGB(226, 72, 60),
	signText = Color3.fromRGB(255, 250, 238),
	fence = Color3.fromRGB(244, 244, 240),
	spawn = Color3.fromRGB(246, 196, 64),
}

function Theme.rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- A paper card with an ink outline and rounded corners.
function Theme.card(frame, color)
	frame.BackgroundColor3 = color or Theme.PAPER
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CORNER)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.INK
	stroke.Thickness = Theme.OUTLINE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return frame
end

-- A plain text label with sensible defaults; `props` overrides them.
function Theme.label(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Theme.BODY
	label.TextColor3 = Theme.INK
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	for key, value in pairs(props or {}) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

return Theme
