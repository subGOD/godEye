import React, { useState, useEffect } from 'react';
import { Settings, Activity, Network, Users, Shield, Terminal, Menu, LogOut } from 'lucide-react';
import { AreaChart, Area, PieChart, Pie, ResponsiveContainer, XAxis, YAxis, Tooltip } from 'recharts';

// Mock data - we'll replace this with real PiVPN data later
const mockTrafficData = [
  { name: 'qBittorrent', download: 12.8, upload: 4.14, total: 16.9, color: '#00ff00' },
  { name: 'SSL/TLS', download: 7.87, upload: 0.492, total: 8.37, color: '#4a90e2' },
  { name: 'Youtube', download: 4.45, upload: 0.423, total: 4.49, color: '#ff0000' },
  { name: 'Docker', download: 3.47, upload: 0.170, total: 3.49, color: '#1bc' }
];

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
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [networkData, setNetworkData] = useState([]);
  const [logs, setLogs] = useState([]);

  useEffect(() => {
    const user = localStorage.getItem('user');
    if (user) {
      setIsAuthenticated(true);
    }
  }, []);

  const handleLogin = (user) => {
  	setIsAuthenticated(true);
  	localStorage.setItem('user', JSON.stringify(user));
	};

  const handleLogout = () => {
    setIsAuthenticated(false);
    localStorage.removeItem('user');
  };

  useEffect(() => {
    if (!isAuthenticated) return;

    const initialData = Array(50).fill(null).map((_, i) => ({
      time: new Date(Date.now() - (49 - i) * 1000),
      up: 0,
      down: 0
    }));
    setNetworkData(initialData);

    const interval = setInterval(() => {
      setNetworkData(prevData => {
        const newData = [...prevData.slice(1), {
          time: new Date(),
          up: Math.floor(Math.random() * 20),
          down: Math.floor(Math.random() * 30)
        }];
        return newData;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isAuthenticated]);

  const Header = () => (
    <div className="h-14 bg-[#242424] border-b border-[#333] flex items-center justify-between px-4 fixed w-full top-0 z-50">
      <div className="flex items-center gap-3">
        <button onClick={() => setSidebarOpen(!sidebarOpen)} className="p-2 hover:bg-[#333] rounded-md">
          <Menu className="h-5 w-5 text-gray-400" />
        </button>
        <span className="text-[15px] text-white font-bold">godEye</span>
      </div>
      <div className="flex items-center gap-4">
        <span className="text-white font-medium">Hello, subGOD</span>
        <span className="text-xs px-3 py-1.5 bg-[#333] rounded text-white">
          {new Date().toLocaleTimeString()} GMT+2
        </span>
        <Network className="h-5 w-5 text-blue-400" />
        <Settings className="h-5 w-5 text-gray-400" />
        <button 
          onClick={handleLogout}
          className="text-red-400 hover:text-red-300"
        >
          <LogOut className="h-5 w-5" />
        </button>
      </div>
    </div>
  );

  const Sidebar = () => (
    <div className={`fixed left-0 top-14 h-[calc(100vh-56px)] w-64 bg-[#242424] border-r border-[#333] transition-transform duration-300 ${sidebarOpen ? 'translate-x-0' : '-translate-x-64'}`}>
      <nav className="p-4">
        <div className="space-y-2">
          <NavItem icon={Activity} text="Dashboard" active />
          <NavItem icon={Users} text="Clients" />
          <NavItem icon={Shield} text="Security" />
          <NavItem icon={Terminal} text="Console" />
        </div>
      </nav>
    </div>
  );

  const NavItem = ({ icon: Icon, text, active }) => (
    <a
      href="#"
      className={`flex items-center gap-3 px-3 py-2 rounded-md transition-colors
        ${active 
          ? 'bg-blue-500/10 text-blue-400' 
          : 'text-gray-400 hover:bg-[#333] hover:text-white'
        }`}
    >
      <Icon className="h-5 w-5" />
      <span>{text}</span>
    </a>
  );

  const StatCard = ({ title, value }) => (
    <div className="bg-[#242424] rounded-lg p-4 border border-[#333]">
      <h3 className="text-gray-400 text-sm mb-1">{title}</h3>
      <p className="text-2xl text-white">{value}</p>
    </div>
  );

  const ChartCard = ({ title, chart }) => (
    <div className="bg-[#242424] rounded-lg p-4 border border-[#333]">
      <h3 className="text-gray-400 text-sm mb-4">{title}</h3>
      {chart}
    </div>
  );

  const NetworkChart = () => (
    <ResponsiveContainer width="100%" height={200}>
      <AreaChart data={networkData}>
        <XAxis 
          dataKey="time"
          tickFormatter={(time) => time.toLocaleTimeString()}
          interval={10}
          stroke="#666"
        />
        <YAxis stroke="#666" />
        <Tooltip
          labelFormatter={(label) => new Date(label).toLocaleTimeString()}
          formatter={(value, name) => [`${value} Mbps`, name === 'up' ? 'Upload' : 'Download']}
          contentStyle={{ backgroundColor: '#242424', border: '1px solid #333' }}
          itemStyle={{ color: '#fff' }}
        />
        <Area 
          type="monotone" 
          dataKey="down" 
          stroke="#4a90e2" 
          fill="#4a90e2" 
          fillOpacity={0.1} 
          name="Download"
        />
        <Area 
          type="monotone" 
          dataKey="up" 
          stroke="#ff6b6b" 
          fill="#ff6b6b" 
          fillOpacity={0.1} 
          name="Upload"
        />
      </AreaChart>
    </ResponsiveContainer>
  );

  const TrafficChart = () => (
    <ResponsiveContainer width="100%" height={200}>
      <PieChart>
        <Pie
          data={mockTrafficData}
          dataKey="total"
          cx="50%"
          cy="50%"
          innerRadius={60}
          outerRadius={80}
          fill="#8884d8"
        />
        <Tooltip
          contentStyle={{ backgroundColor: '#242424', border: '1px solid #333' }}
          itemStyle={{ color: '#fff' }}
        />
      </PieChart>
    </ResponsiveContainer>
  );

  const ClientList = () => (
    <div className="bg-[#242424] rounded-lg p-4 border border-[#333]">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-gray-400 text-sm">Connected Clients</h3>
        <button className="px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600">
          Add Client
        </button>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="text-gray-400 text-sm">
              <th className="text-left pb-3">Name</th>
              <th className="text-left pb-3">IP Address</th>
              <th className="text-left pb-3">Connected Since</th>
              <th className="text-left pb-3">Data Usage</th>
              <th className="text-left pb-3">Status</th>
              <th className="text-left pb-3">Actions</th>
            </tr>
          </thead>
          <tbody className="text-white">
            <tr className="border-t border-[#333]">
              <td className="py-3">iPhone</td>
              <td>10.8.0.2</td>
              <td>2h 15m</td>
              <td>1.2 GB</td>
              <td>
                <span className="px-2 py-1 bg-green-500/10 text-green-400 rounded-full text-sm">
                  Active
                </span>
              </td>
              <td>
                <button className="text-red-400 hover:text-red-300">
                  Disconnect
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  );

  const LogsView = () => (
    <div className="bg-[#242424] rounded-lg p-4 border border-[#333] mt-6">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-gray-400 text-sm">System Logs</h3>
        <button className="text-blue-400 hover:text-blue-300 text-sm">
          Export Logs
        </button>
      </div>
      <div className="overflow-y-auto max-h-[400px] font-mono text-sm">
        {logs.map((log, index) => (
          <div 
            key={index}
            className={`py-2 border-b border-[#333] ${
              log.type === 'warning' ? 'text-yellow-400' :
              log.type === 'error' ? 'text-red-400' :
              'text-green-400'
            }`}
          >
            <span className="text-gray-500">
              {log.timestamp.toLocaleTimeString()}
            </span>{' '}
            {log.message}
          </div>
        ))}
      </div>
    </div>
  );

  const MainContent = () => (
    <div className="ml-64 pt-14 pb-16 p-6 bg-[#1a1a1a] min-h-[calc(100vh-56px)]">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <StatCard title="Active Clients" value="18" />
        <StatCard title="Total Traffic" value="41.6 GB" />
        <StatCard title="Download Speed" value="125 Mbps" />
        <StatCard title="Upload Speed" value="45 Mbps" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <ChartCard title="Network Activity" chart={<NetworkChart />} />
        <ChartCard title="Traffic Distribution" chart={<TrafficChart />} />
      </div>

      <ClientList />
      <LogsView />
    </div>
  );

  const Footer = () => (
    <div className="fixed bottom-0 left-0 right-0 h-12 bg-[#242424] border-t border-[#333] flex items-center justify-center text-sm z-50">
      <span className="text-gray-400">
        <span className="font-bold text-white">godEye</span> by{" "}
        <a 
          href="https://github.com/subGOD" 
          target="_blank" 
          rel="noopener noreferrer"
          className="text-blue-400 hover:text-blue-300 font-medium"
        >
          subGOD
        </a>
      </span>
    </div>
  );

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
