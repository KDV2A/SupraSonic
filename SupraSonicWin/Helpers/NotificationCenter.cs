using System;
using System.Collections.Generic;

namespace SupraSonicWin.Helpers
{
    public class Notification
    {
        public string Name { get; }
        public Notification(string name) { Name = name; }
    }

    public class NotificationCenter
    {
        public static NotificationCenter Default { get; } = new NotificationCenter();

        private Dictionary<string, Action<Notification>> m_observers = new Dictionary<string, Action<Notification>>();

        public void AddObserver(string name, Action<Notification> action)
        {
            if (!m_observers.ContainsKey(name))
                m_observers[name] = action;
            else
                m_observers[name] += action;
        }

        public void Post(Notification notification)
        {
            if (m_observers.ContainsKey(notification.Name))
                m_observers[notification.Name]?.Invoke(notification);
        }
    }
}
