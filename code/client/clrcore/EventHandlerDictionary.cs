using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace CitizenFX.Core
{
    public class EventHandlerDictionary : Dictionary<string, EventHandlerEntry>
    {
        public new EventHandlerEntry this[string key]
        {
            get
            {
                var lookupKey = key.ToLower();

                if (this.ContainsKey(lookupKey))
                {
                    return base[lookupKey];
                }

                var entry = new EventHandlerEntry(key);
                base.Add(lookupKey, entry);

                return entry;
            }
            set
            {
                // no operation
            }
        }

        public void Add(string key, Delegate value)
        {
            this[key] += value;
        }

        internal async Task Invoke(string eventName, string sourceString, object[] arguments)
        {
            var lookupKey = eventName.ToLower();
            EventHandlerEntry entry;
            
            if (TryGetValue(lookupKey, out entry))
            {
                await entry.Invoke(sourceString, arguments);
            }
        }
    }

    public class EventHandlerEntry
    {
        private readonly string m_eventName;
        private readonly List<Delegate> m_callbacks = new List<Delegate>();

        public EventHandlerEntry(string eventName)
        {
            m_eventName = eventName;
        }

        public static EventHandlerEntry operator +(EventHandlerEntry entry, Delegate deleg)
        {
            entry.m_callbacks.Add(deleg);

            return entry;
        }

        public static EventHandlerEntry operator -(EventHandlerEntry entry, Delegate deleg)
        {
            entry.m_callbacks.Remove(deleg);

            return entry;
        }

        internal async Task Invoke(string sourceString, params object[] args)
        {
            var callbacks = m_callbacks.ToArray();

            foreach (var callback in callbacks)
            {
                try
                {
					List<object> passArgs = new List<object>();

					var argIdx = 0;

					object ChangeType(object value, Type type)
					{
						if (value.GetType().IsAssignableFrom(type))
						{
							return value;
						}
						else if (value is IConvertible)
						{
							return Convert.ChangeType(value, type);
						}

						throw new InvalidCastException($"Could not cast event argument for {m_eventName} from {value.GetType().Name} to {type.Name}");
					}

					object Default(Type type) => type.IsValueType ? Activator.CreateInstance(type) : null;

					foreach (var info in callback.Method.GetParameters())
					{
						var type = info.ParameterType;

						if (info.GetCustomAttribute<FromSourceAttribute>() != null)
						{
							// empty source -> default
							if (string.IsNullOrWhiteSpace(sourceString))
							{
								passArgs.Add(Default(type));
								
								continue;
							}

#if IS_FXSERVER
							if (type.IsAssignableFrom(typeof(Player)))
							{
								passArgs.Add(new Player(sourceString));

								continue;
							}
#endif

							passArgs.Add(ChangeType(sourceString, type));
						}
						else
						{
							if (argIdx >= args.Length)
							{
								passArgs.Add(Default(type));
							}
							else
							{
								passArgs.Add(ChangeType(args[argIdx], type));
							}

							argIdx++;
						}
					}

					var rv = callback.DynamicInvoke(passArgs.ToArray());

					if (rv != null && rv is Task task)
					{
						await task;
					}
                }
                catch (Exception e)
                {
                    Debug.WriteLine("Error invoking callback for event {0}: {1}", m_eventName, e.ToString());

                    m_callbacks.Remove(callback);
                }
            }
        }
    }
}
