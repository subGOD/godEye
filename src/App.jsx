import React, { useState, useEffect } from 'react';
import { Settings, Activity, Network, Users, Shield, Terminal, Menu, LogOut } from 'lucide-react';
import { AreaChart, Area, PieChart, Pie, ResponsiveContainer, XAxis, YAxis, Tooltip } from 'recharts';

// Components
const Login = ({ onLogin }) => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (username === 'subGOD' && password === 'test') {
      onLogin(username);
    } else {
      setError('Invalid credentials');
    }
  };

  return (
    <div className="min-h-screen bg-[#1a1a1a] flex items-center justify-center px-4">
      <div className="bg-[#242424] p-8 rounded-lg border border-[#333] w-full max-w-md">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-white mb-2">godEye</h1>
          <p className="text-gray-400">PiVPN Management Interface</p>
        </div>
        
        {error && (
          <div className="mb-4 p-3 bg-red-500/10 border border-red-500/20 rounded text-red-400 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-gray-400 text-sm mb-2">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full bg-[#333] border border-[#444] rounded px-3 py-2 text-white focus:outline-none focus:border-blue-500"
              required
            />
          </div>
          
          <div>
            <label className="block text-gray-400 text-sm mb-2">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full bg-[#333] border border-[#444] rounded px-3 py-2 text-white focus:outline-none focus:border-blue-500"
              required
            />
          </div>

          <button
            type="submit"
            className="w-full bg-blue-500 text-white rounded py-2 hover:bg-blue-600 transition-colors"
          >
            Login
          </button>
        </form>
      </div>
    </div>
  );
};

function App() {
  // State management
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [networkData, setNetworkData] = useState([]);
  const [vpnClients, setVpnClients] = useState([]);
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Check for existing session
  useEffect(() => {
    const user = localStorage.getItem('user');
    if (user) {
      setIsAuthenticated(true);
    }
  }, []);

  // Fetch VPN data
  useEffect(() => {
    if (!isAuthenticated) return;

    const fetchVPNData = async () => {
      try {
        const response = await fetch('http://localhost:3000/api/vpn-status');
        const data = await response.json();
        setVpnClients(data);
        setLoading(false);
      } catch (err) {
        setError('Failed to fetch VPN data');
        setLoading(false);
      }
    };

    fetchVPNData();
    const interval = setInterval(fetchVPNData, 5000); // Refresh every 5 seconds

    return () => clearInterval(interval);
  }, [isAuthenticated]);

  // Network data monitoring
  useEffect(() => {
    if (!isAuthenticated) return;

    const fetchNetworkData = async () => {
      // Here we'll add real network monitoring data
      // For now, using mock data
      const newData = {
        time: new Date(),
        up: Math.floor(Math.random() * 20),
        down: Math.floor(Math.random() * 30)
      };

      setNetworkData(prev => [...prev.slice(-49), newData]);
    };

    const interval = setInterval(fetchNetworkData, 1000);
    return () => clearInterval(interval);
  }, [isAuthenticated]);

  const handleLogin = (username) => {
    setIsAuthenticated(true);
    localStorage.setItem('user', username);
  };

  const handleLogout = () => {
    setIsAuthenticated(false);
    localStorage.removeItem('user');
  };

  // Components remain mostly the same, updating ClientList for real data
  const ClientList = () => (
    <div className="bg-[#242424] rounded-lg p-4 border border-[#333]">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-gray-400 text-sm">Connected Clients</h3>
        <button className="px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600">
          Add Client
        </button>
      </div>
      {loading ? (
        <div className="text-center py-4 text-gray-400">Loading clients...</div>
      ) : error ? (
        <div className="text-center py-4 text-red-400">{error}</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-gray-400 text-sm">
                <th className="text-left pb-3">Name</th>
                <th className="text-left pb-3">Remote IP</th>
                <th className="text-left pb-3">Virtual IP</th>
                <th className="text-left pb-3">Data Received</th>
                <th className="text-left pb-3">Data Sent</th>
                <th className="text-left pb-3">Last Seen</th>
                <th className="text-left pb-3">Actions</th>
              </tr>
            </thead>
            <tbody className="text-white">
              {vpnClients.map((client) => (
                <tr key={client.name} className="border-t border-[#333]">
                  <td className="py-3">{client.name}</td>
                  <td>{client.remoteIP}</td>
                  <td>{client.virtualIP}</td>
                  <td>{client.bytesReceived}</td>
                  <td>{client.bytesSent}</td>
                  <td>{client.lastSeen}</td>
                  <td>
                    <button className="text-red-400 hover:text-red-300">
                      Disconnect
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );

  // Rest of your components remain the same...
  // [Previous Header, Sidebar, NavItem, StatCard, ChartCard, NetworkChart, TrafficChart, LogsView components]

  return (
    <div className="min-h-screen bg-[#1a1a1a] relative">
      {!isAuthenticated ? (
        <Login onLogin={handleLogin} />
      ) : (
        <div className="content-wrapper">
          <Header />
          <Sidebar />
          <MainContent />
          <Footer />
        </div>
      )}
    </div>
  );
}

export default App;
