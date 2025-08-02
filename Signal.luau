--!strict
--!optimize 2
--!native

export type SignalConnection = {
	Disconnect: () -> ()
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, (T...) -> ()) -> SignalConnection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({
		_handlers = {}
	}, Signal)
end

function Signal:Connect(fn: (T...) -> ()): SignalConnection
	table.insert(self._handlers, fn)
	return {
		Disconnect = function()
			for i, handler in ipairs(self._handlers) do
				if handler == fn then
					table.remove(self._handlers, i)
					break
				end
			end
		end
	}
end

function Signal:Fire(...: T...)
	for _, handler in ipairs(self._handlers) do
		-- Use task.spawn to avoid yielding the caller if handler yields or errors
		task.spawn(handler, ...)
	end
end

return Signal
