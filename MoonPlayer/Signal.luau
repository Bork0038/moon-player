--!optimize 2
--!strict
export type Signal<T...> = {
	Fire: (self: Signal<T...>, T...) -> (),
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> RBXScriptConnection,
	ConnectParallel: (self: Signal<T...>, callback: (T...) -> ()) -> RBXScriptConnection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> RBXScriptConnection,
	Wait: (self: Signal<T...>) -> T...,
	Destroy: (self: Signal<T...>) -> (),
}

const Signal = {}

const function indexEvent(event: any, key: string): any
	return event[key]
end

const CUSTOM = {
	Fire = function(self: any, ...: any): ()
		if rawget(self, "_destroyed") then
			return
		end

		task.defer(self._bindable.Fire, self._bindable, ...)
	end,

	Destroy = function(self: any): ()
		rawset(self, "_destroyed", true)
		self._bindable:Destroy()
	end,
}

function Signal.new<T...>(): Signal<T...>
	const bindable = Instance.new("BindableEvent")
	const event = bindable.Event

	return setmetatable({ _bindable = bindable }, {
		__newindex = function(self: any, key: string, value: any): ()
			return error(("Cannot set property '%s' on Signal"):format(key))
		end,
		__index = function(self: any, key: string): any
			const custom = CUSTOM[key]
			if custom then
				return custom
			end

			const ok, member = pcall(indexEvent, event, key)
			if not ok then
				return nil
			end

			if typeof(member) == "function" then
				const bound = function(_: any, ...: any): any
					return member(event, ...)
				end

				rawset(self, key, bound)
				return bound
			end

			return member
		end,
	}) :: any
end

return Signal
