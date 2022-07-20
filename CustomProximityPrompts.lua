--[[
author: samuelagent

This library handles UI interactions on the client. You require it once and all custom-style proximity prompts will
utilize the custom Gui Prompts. Proximity Prompts still function normally in that their events fire (So you can use
normal ProximityPrompt / ProximityPromptService Events and Functions).

Have some API
----------------------------------------------------------------------------------------------------------------------
EVENT > promptTriggered(Prompt: Instance, PromptGui: Instance)
	Fires whenever a prompt is triggered by the client. Passes the ProximityPrompt as the first parameter, and the
	custom GUI as the second. Note that the PromptGui will be destroyed once the player is unable to see it for any
	reason, such as Field of View, disabling the ProximityPrompt, or distance.

EVENT > promptTriggerEnded(Prompt: Instance, PromptGui: Instance)
	Fires whenever a trigger ends, usually when you've let go of the activation button. Same parameters passed as
	promptTriggered.
	
EVENT > promptShown(Prompt: Instance, PromptGui: Instance)
	Fires when a prompt is shown, or more specifically when the GUI is constructed and shown. Same parameters passed
	as PrompTriggered.

EVENT > promptHidden(Prompt: Instance)
	Fires when a prompt is hidden due to any reason. You don't get PromptGui as a parameter because it is destroyed
	right after the event fires.
	
(You shouldn't really have to use these functions)

FUNCTION > [BillboardGui] Interaction:ShowPrompt(Prompt: Instance, InputType: ProximityPromptInputType)
	Creates a new prompt gui for the referenced Prompt Instance, the ProximityPromptInputType is the type of input
	which the ProximityPrompt uses to process input, either touch or keyboard. This function returns the PromptGui
	(Instance) it creates and fires the promptShown Event.

FUNCTION > Interaction:HidePrompt(Prompt: Instance, PromptGui: Instance)
	Hides the referenced prompt gui and disconnects internal connections. Will fire the promptHidden Event.
	
	
----------------------------------------------------------------------------------------------------------------------
Quick Note *

For the events, the documentation says that Proximity Prompts pass the player who caused the event as a parameter.
I've tested this myself just to be sure, and it looks like this only matters if the event is connected from the
server, clients will only ever be able to read the event when it has been triggered themselves, which is why there
is no PlayerWhoTriggered == LocalPlayer check, there is no reason to have one, however I think this is something
still worth noting.

]]


--// Services
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--// Folders
local Miscellaneous = ReplicatedStorage:WaitForChild("Miscellaneous")

--// Instances
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local PromptGuiTemplate = Miscellaneous:WaitForChild("CustomPrompt")

local TouchIcon = "rbxasset://textures/ui/controls/TouchTapIcon.png"
local TriggerTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TriggerColor = Color3.fromRGB(255, 255, 255) -- BackgroundColor Tween of Prompt Trigger
local TriggerTransparency = 0.3 -- TextTransparency / Border Transparency Tween of prompt Trigger

--// Bindables (For Custom Events)
local promptTriggeredBindable = Instance.new("BindableEvent")
local promptTriggerEndedBindable = Instance.new("BindableEvent")
local promptShownBindable = Instance.new("BindableEvent")
local promptHiddenBindable = Instance.new("BindableEvent")

--> Module <--
local Interaction = {}

--// Runtime Variables

Interaction.buttonDown = false
Interaction.promptHolding = false

--// Connections

Interaction.promptHiddenConnection = nil

Interaction.triggerEndedConnection = nil
Interaction.triggeredConnection = nil

Interaction.holdBeganConnection = nil
Interaction.holdEndedConnection = nil

--// Events

Interaction.promptTriggered = promptTriggeredBindable.Event
Interaction.promptTriggerEnded = promptTriggerEndedBindable.Event

Interaction.promptShown = promptShownBindable.Event
Interaction.promptHidden = promptHiddenBindable.Event

--// Methods
function Interaction:ShowPrompt(Prompt, InputType)
	local PromptGui = PromptGuiTemplate:Clone()
	PromptGui.Name = "DisplayPrompt"
	PromptGui.Parent = PlayerGui

	promptShownBindable:Fire(Prompt, PromptGui)
	PromptGui:SetAttribute("Percentage", 0)
	PromptGui.Enabled = true

	local TextButton = PromptGui.ProgressFrame.TextButton

	local TriggeredTween = TweenService:Create(TextButton, TriggerTweenInfo, {BackgroundColor3 = TriggerColor})
	local TriggerEndTween = TweenService:Create(TextButton, TriggerTweenInfo, {BackgroundColor3 = TextButton.BackgroundColor3})
	local TriggeredTweenText = TweenService:Create(TextButton, TriggerTweenInfo, {TextTransparency = TriggerTransparency})
	local TriggerEndTweenText = TweenService:Create(TextButton, TriggerTweenInfo, {TextTransparency = TextButton.TextTransparency})
	local TriggeredTweenBorder = TweenService:Create(TextButton.UIStroke, TriggerTweenInfo, {Transparency = TriggerTransparency})
	local TriggerEndTweenBorder = TweenService:Create(TextButton.UIStroke, TriggerTweenInfo, {Transparency = TextButton.UIStroke.Transparency})

	if InputType == Enum.ProximityPromptInputType.Touch then
		TextButton.Text = ""
		TextButton.Icon.Image = TouchIcon
	elseif InputType == Enum.ProximityPromptInputType.Keyboard then
		local InputText = UserInputService:GetStringForKeyCode(Prompt.KeyboardKeyCode)

		TextButton.Text = InputText
		TextButton.Icon.Image = ""

		if InputText == "" then
			warn("ProximityPrompt \"" .. Prompt.Name .. "\" requires an unknown keyboard keycode. Child of " .. Prompt.Parent.Name)
			TextButton.Text = "?"
		end
	end

	PromptGui.ProgressFrame.InputBegan:Connect(function(Input) -- Didn't assign connection variables because garbage collector
		if Input.UserInputState == Enum.UserInputState.Change then return end
		if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.promptHolding = true
			self.buttonDown = true
			Prompt:InputHoldBegin()
		end
	end)
	PromptGui.ProgressFrame.InputEnded:Connect(function(Input) -- Didn't assign connection variables because garbage collector
		if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.buttonDown then
				self.promptHolding = false
				self.buttonDown = false
				Prompt:InputHoldEnd()
			end
		end
	end)

	PromptGui.Adornee = Prompt.Parent

	if Prompt.HoldDuration > 0 then
		self.holdBeganConnection = Prompt.PromptButtonHoldBegan:Connect(function()
			local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
			
			if Humanoid and Humanoid.Health > 0 then
				self.promptHolding = true
				
				local StartOs = os.clock()
				local NeededOffset = os.clock() - math.asin(0)

				while self.promptHolding do
					local Scale = 1 + math.sin(os.clock() - NeededOffset)/4
					PromptGui.ProgressFrame.Size = UDim2.new(Scale,0,Scale,0)
					PromptGui:SetAttribute("Percentage", ((os.clock() - StartOs)/Prompt.HoldDuration) * 100)
					
					task.wait()
				end				
			end
		end)

		self.holdEndedConnection = Prompt.PromptButtonHoldEnded:Connect(function() -- Fires When Trigger Fires, or Hold Ends Prematurely
			local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
			if Humanoid and Humanoid.Health > 0 then
				self.promptHolding = false
				PromptGui:SetAttribute("Percentage", 0)
				PromptGui.ProgressFrame.Size = UDim2.new(1,0,1,0)				
			end
		end)
	end
	self.triggeredConnection = Prompt.Triggered:Connect(function()
		local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
		if Humanoid and Humanoid.Health > 0 then
			promptTriggeredBindable:Fire(Prompt, PromptGui)

			PromptGui:SetAttribute("Percentage", 100)
			PromptGui.ProgressFrame.Size = UDim2.new(1,0,1,0)
			TriggeredTweenBorder:Play()
			TriggeredTweenText:Play()
			TriggeredTween:Play()			
		end
	end)
	self.triggerEndedConnection = Prompt.TriggerEnded:Connect(function() -- Fires after you've already triggered, then let go
		promptTriggerEndedBindable:Fire(Prompt, PromptGui)
		PromptGui.ProgressFrame.Size = UDim2.new(1,0,1,0)

		PromptGui:SetAttribute("Percentage", 0)
		TriggerEndTweenBorder:Play()
		TriggerEndTweenText:Play()
		TriggerEndTween:Play()
	end)
	self.promptHiddenConnection = Prompt.promptHidden:Connect(function() -- Prompt goes out of focus and disappears
		Interaction:HidePrompt(Prompt, PromptGui)
	end)

	return PromptGui
end

function Interaction:HidePrompt(Prompt, PromptGui)
	promptHiddenBindable:Fire(Prompt)
	if self.holdBeganConnection then self.holdBeganConnection:Disconnect() end
	if self.holdEndedConnection then self.holdEndedConnection:Disconnect() end
	self.promptHiddenConnection:Disconnect()
	self.triggerEndedConnection:Disconnect()
	self.triggeredConnection:Disconnect()
	PromptGui:Destroy()
end


ProximityPromptService.promptShown:Connect(function(Prompt, InputType)
	if Prompt.Style == Enum.ProximityPromptStyle.Default then return end
	Interaction:ShowPrompt(Prompt, InputType)
end)

return Interaction
