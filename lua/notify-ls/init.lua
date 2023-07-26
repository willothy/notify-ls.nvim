---@class Client
---- LSP Server Description -----
---@field name string
---@field autostart boolean
---@field settings table<string, any>
---@field filetypes string[]
----- Neovim LSP Interface ------
---@field on_attach function
---@field before_init function
---@field on_init function
---@field on_exit function
------ LSP Client Interface -----
---@field request function
---@field notify function
---@field is_closing function
---@field terminate function
-------- Internal fields --------
---@field _dispatchers table<string, fun(...)>
---@field _capabilities lsp.ServerCapabilities
---@field _started boolean
---@field _stopped boolean
---@field _client_id number
---@field _free_id number
---@field _root_dir fun(): string
---@field _receivers table<string, func(any)[]>
---@field _active table<integer, Progress>
local Client = {
	name = "notify",
	autostart = true,
	filetypes = {},
	_capabilities = {
		window = {
			workDoneProgress = true,
			showMessage = true,
			showDocument = true,
		},
		referencesProvider = {
			workDoneProgress = true,
		},
		definitionProvider = {
			workDoneProgress = true,
		},
		textDocument = {
			formatting = {
				dynamicRegistration = true,
			},
		},
	},
	_started = false,
	_stopped = false,
	_free_id = 1,
	_receivers = {},
}

function Client._root_dir()
	return vim.fn.getcwd()
end

---@return integer
function Client._next_id()
	local id = Client._free_id
	Client._free_id = id + 1
	return id
end

---@param method string
---@param params table<string, any>
---@param cb fun(...)
---@return boolean, integer
function Client._handle(method, params, cb)
	vim.print(method)
	local id = Client._next_id()

	if method == "initialize" then
		if cb then
			cb(nil, { capabilities = Client._capabilities })
		end
	elseif method == "exit" then
		Client.terminate()
		if cb then
			cb()
		end
	elseif Client._receivers[method] then
		for _, receiver in pairs(Client._receivers[method]) do
			receiver(params, cb)
		end
	end

	return true, id
end

---@param method string
---@param params table<string, any>
---@param cb fun(...)
---@param notify_cb fun(...)
---@return boolean, integer
function Client.request(method, params, cb, notify_cb)
	local ok, id = Client._handle(method, params, cb)
	if ok and notify_cb then
		vim.schedule(function()
			notify_cb(id)
		end)
	end

	return ok, id
end

---@param method string
---@param params table<string, any>
function Client.notify(method, _params)
	return Client._handle(method, params)
end

---@return boolean
function Client.is_closing()
	return Client._stopped
end

function Client.terminate()
	Client._stopped = true
end

---Called when the server is attached to a buffer.
function Client.on_attach()
	vim.print("notify-ls attached")
end

---Called before the server is initialized.
function Client.before_init()
	vim.print("notify-ls before init")
end

---Called when the server is initialized.
function Client.on_init()
	vim.print("notify-ls started")
end

---Called when the server is exited.
function Client.on_exit()
	vim.print("notify-ls exited")
end

-- This is called by Neovim to "start" the server
function Client.cmd(dispatchers)
	Client._dispatchers = dispatchers
	return Client
end

function Client.start(settings)
	if Client._started == false and Client._stopped == false then
		Client.root_dir = Client._root_dir()
		Client.settings = settings or {}
		local id = vim.lsp.start(Client)
		if not id then
			vim.print("failed to start client")
			return
		end
		Client._started = true
		Client._client_id = id
		return id
	else
		return Client._client_id
	end
end

function Client.create_progress(title, message, percentage)
	if not Client._active then
		Client._active = {}
	end
	local progress = {
		kind = "begin",
		id = Client._next_id(),
		title = title,
		message = message,
		percentage = percentage,
	}

	local function send()
		vim.lsp.handlers["$/progress"](nil, { token = progress.id, value = progress }, { client_id = Client.start() })
	end

	function progress:start()
		send()
	end

	function progress:update(opts)
		if not opts then
			return
		end
		for k, v in pairs(opts) do
			if k ~= "id" then
				self[k] = v
			end
		end
		send()
	end

	function progress:finish(msg)
		self.kind = "end"
		self.message = msg
		send()
	end

	return progress
end

local recv_id = 1
function Client.create_receiver(method, handler)
	local id = recv_id
	recv_id = recv_id + 1
	if not Client._receivers[method] then
		Client._receivers[method] = {}
	end
	Client._receivers[method][id] = handler
	return id
end

function Client.remove_receiver(method, id)
	if Client._receivers[method] then
		Client._receivers[method][id] = nil
	end
end

Client.start()

local client = vim.lsp.get_client_by_id(Client._client_id)
cap = client.dynamic_capabilities.new(Client._client_id)
cap.capabilities.textDocument = {}
cap.capabilities.textDocument.references = {}
cap.capabilities.textDocument.references.dynamicRegistration = true
client.handlers["textDocument/references"] = function()
	vim.print("test")
end
Client.create_receiver("textDocument/references", function()
	local p = Client.create_progress("indexing", "", 0)

	local t = vim.loop.new_timer()

	p:start()
	local nfiles = math.random(15, 60)
	local n = 0
	t:start(
		200,
		100,
		vim.schedule_wrap(function()
			n = n + 1
			p:update({
				message = string.format("%s / %s", n, nfiles),
				percentage = math.floor((n / nfiles) * 100),
			})
			if p.percentage == 100 then
				p:finish("done")
				t:stop()
			end
		end)
	)
end)

return Client
