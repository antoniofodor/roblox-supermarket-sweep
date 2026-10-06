-- Big Chonk, grey box: a giant placeholder ball outside the front window,
-- looking in. The real model is the designer's job; until then he is a body,
-- two eyes, a mouth, a name and a speech bubble, and everything he does is
-- words: shouts by name, his craving, the food he's tired of, reactions, and
-- his verdicts at the feeding.
--
-- Also builds what stands around him outside: the line players stand in to
-- be fed, the stands the eaten wait in, and the podium.
--
-- A leaf like Fx: it requires only Shared, Fx and Store, so Shoppers, Fights
-- and Round can all call it without a cycle.
--
-- Layout (studs, z relative to the store's front wall Store.FRONT_Z):
--   Chonk       x 0, z +50, just past the lobby fence, facing the window
--   feed line   z +35, in front of him, facing him
--   podium      x -36 .. -24, z +40
--   stands      x 52 .. 76, z +8 .. +18, facing the window

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Remotes = require(Shared.Remotes)

local Store = require(script.Parent.Store)
local Fx = require(script.Parent.Fx)

local Chonk = {}

local RADIUS = 9
local rng = Random.new()

local folder
local body
local bubble -- TextLabel in his speech bubble
local remote
local lastReact = -math.huge
local mood = "calm"

local MOOD_COLORS = {
	calm = Color3.fromRGB(240, 170, 90),
	grumpy = Color3.fromRGB(232, 128, 60),
	furious = Color3.fromRGB(214, 70, 50),
	happy = Color3.fromRGB(236, 130, 170),
}

-- What he says. %s is filled in by whoever calls; every line is short
-- enough to read in a bubble at a glance.
local LINES = {
	hungry = { "I'M SO HUNGRY! FEED ME!", "FOOD! NOW! PLEASE!", "MY TUMMY IS RUMBLING!" },
	notToday = { "NO %s TODAY! I'M SICK OF IT!", "DON'T BRING ME %s! NOT TODAY!" },
	missing = { "%s! WHERE'S MY %s?", "%s! I NEED %s!", "%s, DON'T FORGET MY %s!" },
	listDone = { "%s! MORE SNACKS!", "%s! YES! KEEP GOING!", "%s! GET IT TO THE TILL!" },
	craving = { "I WANT %s! %s IS TRIPLE YUM NOW!" },
	tantrum = { "RAAAAH! I'M SO HUNGRY!", "*SLAM* WHERE IS MY FOOD?!" },
	furious = { "HURRY UP!", "I'M STARVING!", "THE SHUTTERS ARE COMING!", "GET OUT HERE WITH MY FOOD!" },
	ram = { "OOH! BIG CRASH!", "HA! DO IT AGAIN!", "WHAT A SMASH!" },
	yuck = { "EWW! %s TOUCHED THE %s!", "%s, KEEP THAT %s AWAY FROM ME!" },
	sabotage = { "HA! RIGHT IN THE TROLLEY!", "SNEAKY! I LIKE IT!" },
	love = { "MMM! %s, I LOVE IT!", "*BELLY DRUM* %s IS MY FAVOURITE!" },
	content = { "Hmm. Not bad, %s.", "*shrug* OK, %s." },
	angry = { "BLEURGH! %s, WHAT IS THIS?", "%s! YOU CALL THIS FOOD?" },
	nothing = { "%s BROUGHT ME NOTHING!" },
	gulp = { "GULP! Bye bye, %s!" },
	winner = { "%s FED ME BEST! THE WINNER!" },
}

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- A line from LINES with its blanks filled.
function Chonk.line(kind, ...)
	local template = LINES[kind] and pick(LINES[kind]) or kind
	local ok, text = pcall(string.format, template, ...)
	return if ok then text else template
end

local function part(name, size, cf, color, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(opts or {}) do
		p[key] = value
	end
	p.Parent = folder
	return p
end

local function billboard(adornee, name, size, offset, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.DISPLAY
	label.TextScaled = true
	label.TextColor3 = Theme.INK
	label.Text = ""
	label.Parent = gui
	return gui, label
end

local function z(rel)
	return Store.FRONT_Z + rel
end

function Chonk.build()
	folder = Instance.new("Folder")
	folder.Name = "Outside"
	folder.Parent = Store.root()

	local centre = Vector3.new(0, RADIUS, z(50))
	body = part("BigChonk", Vector3.new(RADIUS * 2, RADIUS * 2, RADIUS * 2), CFrame.new(centre), MOOD_COLORS.calm, {
		Shape = Enum.PartType.Ball,
	})
	-- a face on the side looking at the store (-Z)
	for _, side in ipairs({ -1, 1 }) do
		local eye = Vector3.new(side * 3.5, 12, z(41.6))
		part("Eye", Vector3.new(3, 3, 3), CFrame.new(eye), Color3.new(1, 1, 1), { Shape = Enum.PartType.Ball })
		part("Pupil", Vector3.new(1.4, 1.4, 1.4), CFrame.new(eye + Vector3.new(0, 0, -1.2)), Theme.INK, { Shape = Enum.PartType.Ball })
	end
	part("Mouth", Vector3.new(6, 1.4, 1), CFrame.new(0, 6.5, z(41.2)), Theme.INK)
	-- a flat spot on top of his head, where the winner gets carried
	part("HeadPad", Vector3.new(6, 0.4, 6), CFrame.new(0, RADIUS * 2 + 0.2, z(50)), Color3.new(1, 1, 1), { Transparency = 1 })

	local nameGui, nameLabel = billboard(body, "Name", UDim2.fromScale(16, 3), Vector3.new(0, RADIUS + 1.5, 0), 400)
	nameLabel.Text = "BIG CHONK"
	nameLabel.TextColor3 = Theme.GOLD
	nameLabel.TextStrokeColor3 = Theme.INK
	nameLabel.TextStrokeTransparency = 0
	nameGui.LightInfluence = 0

	local bubbleGui, label = billboard(body, "Speech", UDim2.fromScale(28, 6), Vector3.new(0, RADIUS + 6.5, 0), 400)
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Theme.PAPER
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label
	bubbleGui.Enabled = false
	bubble = label

	-- the podium: 2nd, 1st, 3rd
	for _, spec in ipairs({ { rank = 2, x = -36, h = 3 }, { rank = 1, x = -30, h = 4.5 }, { rank = 3, x = -24, h = 2 } }) do
		local block = part("Podium" .. spec.rank, Vector3.new(5.5, spec.h, 5.5), CFrame.new(spec.x, spec.h / 2, z(40)), Theme.WORLD.sign)
		local _, rankLabel = billboard(block, "Rank", UDim2.fromScale(3, 3), Vector3.new(0, spec.h / 2 + 1.6, 0), 200)
		rankLabel.Text = tostring(spec.rank)
		rankLabel.TextColor3 = Theme.PAPER
	end

	-- the stands: three steps, facing the window
	for step = 1, 3 do
		part("Stand" .. step, Vector3.new(24, step, 3), CFrame.new(64, step / 2, z(8 + step * 3)), Theme.WORLD.fence)
	end
	local sign = part("StandsSign", Vector3.new(24, 2.4, 0.4), CFrame.new(64, 6, z(18.5)), Theme.WORLD.sign)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Theme.DISPLAY
	signText.TextScaled = true
	signText.TextColor3 = Theme.WORLD.signText
	signText.Text = "EATEN BY CHONK"
	signText.Parent = surface

	remote = Remotes.get("ChonkSay")
end

function Chonk.setMood(newMood)
	if MOOD_COLORS[newMood] and newMood ~= mood then
		mood = newMood
		body.Color = MOOD_COLORS[newMood]
	end
end

-- Say something: in his bubble, and on everyone's HUD.
function Chonk.say(text, newMood)
	if newMood then
		Chonk.setMood(newMood)
	end
	bubble.Text = text
	bubble.Parent.Enabled = true
	remote:FireAllClients({ text = text, mood = mood })
end

function Chonk.quiet()
	bubble.Text = ""
	bubble.Parent.Enabled = false
	Chonk.setMood("calm")
end

-- React to something in the store, at most once every CHONK_REACT_GAP.
function Chonk.react(kind, ...)
	local t = os.clock()
	if t - lastReact < Config.CHONK_REACT_GAP or not LINES[kind] then
		return
	end
	lastReact = t
	Chonk.say(Chonk.line(kind, ...))
end

-- Banging on the glass in the last seconds: the window wobbles and thumps.
function Chonk.bang()
	local window = Store.window()
	if window then
		Fx.shake({ window }, Vector3.new(0, 0, -1), window.Position)
		Fx.play("ram", window.Position)
	end
end

-- Where players stand to be fed: a line in front of him, facing him.
function Chonk.lineSpots(count)
	local spots = {}
	local spacing = math.min(4, 44 / math.max(count, 1))
	for i = 1, count do
		local x = (i - (count + 1) / 2) * spacing
		local position = Vector3.new(x, 3, z(35))
		spots[i] = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
	end
	return spots
end

function Chonk.standsSpot()
	local position = Vector3.new(rng:NextNumber(54, 74), 3 + 3, z(17))
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

function Chonk.podiumSpot(rank)
	local spec = ({ { x = -30, h = 4.5 }, { x = -36, h = 3 }, { x = -24, h = 2 } })[rank]
	local position = Vector3.new(spec.x, spec.h + 3, z(40))
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

-- On top of his head: the winner gets carried.
function Chonk.headSpot()
	local position = Vector3.new(0, RADIUS * 2 + 3.4, z(50))
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

-- A crown over the winner's head.
function Chonk.crown(player, on)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("Crown")
	if old then
		old:Destroy()
	end
	if on then
		local gui, label = billboard(head, "Crown", UDim2.fromScale(6, 1.8), Vector3.new(0, 3, 0), 300)
		gui.AlwaysOnTop = true
		label.Text = "WINNER"
		label.TextColor3 = Theme.GOLD
		label.TextStrokeColor3 = Theme.INK
		label.TextStrokeTransparency = 0
	end
end

return Chonk
