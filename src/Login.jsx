import React, { useState, useEffect } from 'react';
import { AlertCircle, Loader2, Shield, Lock } from 'lucide-react';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';

const PasswordRequirements = ({ errors = [] }) => (
    <div className="mt-2 space-y-2">
        <div className="text-sm text-gray-400">
            <p className="flex items-center gap-2">
                <Shield className="h-4 w-4" />
                Password requirements:
            </p>
        </div>
        <ul className="list-disc pl-5 space-y-1 text-sm">
            <li className={cn("text-gray-400", errors.includes('length') && "text-red-400")}>
                At least 8 characters
            </li>
            <li className={cn("text-gray-400", errors.includes('uppercase') && "text-red-400")}>
                One uppercase letter
            </li>
            <li className={cn("text-gray-400", errors.includes('lowercase') && "text-red-400")}>
                One lowercase letter
            </li>
            <li className={cn("text-gray-400", errors.includes('number') && "text-red-400")}>
                One number
            </li>
            <li className={cn("text-gray-400", errors.includes('special') && "text-red-400")}>
                One special character (!@#$%^&*)
            </li>
        </ul>
    </div>
);

const Login = ({ onLogin }) => {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [error, setError] = useState('');
    const [errors, setErrors] = useState([]);
    const [isLoading, setIsLoading] = useState(false);
    const [isSetup, setIsSetup] = useState(true);
    const [passwordStrength, setPasswordStrength] = useState(0);

    useEffect(() => {
        checkSetupStatus();
    }, []);

    useEffect(() => {
        if (!isSetup) {
            validatePassword(password);
        }
    }, [password, isSetup]);

    const checkSetupStatus = async () => {
        try {
            const response = await fetch('/api/setup/status');
            const data = await response.json();
            setIsSetup(data.isSetupComplete);
        } catch (err) {
            console.error('Failed to check setup status:', err);
            setError('Failed to check system status');
        }
    };

    const validatePassword = (pass) => {
        const validationErrors = [];
        let strength = 0;

        if (pass.length < 8) validationErrors.push('length');
        else strength += 20;

        if (!/[A-Z]/.test(pass)) validationErrors.push('uppercase');
        else strength += 20;

        if (!/[a-z]/.test(pass)) validationErrors.push('lowercase');
        else strength += 20;

        if (!/\d/.test(pass)) validationErrors.push('number');
        else strength += 20;

        if (!/[!@#$%^&*(),.?":{}|<>]/.test(pass)) validationErrors.push('special');
        else strength += 20;

        setErrors(validationErrors);
        setPasswordStrength(strength);
    };

    const getPasswordStrengthColor = () => {
        if (passwordStrength <= 20) return 'bg-red-500';
        if (passwordStrength <= 40) return 'bg-orange-500';
        if (passwordStrength <= 60) return 'bg-yellow-500';
        if (passwordStrength <= 80) return 'bg-lime-500';
        return 'bg-green-500';
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setIsLoading(true);
        setError('');
        setErrors([]);

        if (!isSetup) {
            if (password !== confirmPassword) {
                setError('Passwords do not match');
                setIsLoading(false);
                return;
            }

            if (errors.length > 0) {
                setError('Password does not meet requirements');
                setIsLoading(false);
                return;
            }
        }

        try {
            const endpoint = isSetup ? '/api/login' : '/api/setup';
            const payload = { username, password };

            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload),
            });

            const data = await response.json();

            if (response.ok) {
                localStorage.setItem('token', data.token);
                onLogin(data.user);
            } else {
                if (Array.isArray(data.message)) {
                    setErrors(data.message);
                } else {
                    setError(data.message || 'Operation failed');
                }
            }
        } catch (err) {
            console.error('Operation failed:', err);
            setError('Network error. Please check your connection.');
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-gray-900 flex items-center justify-center px-4">
            <div className="bg-gray-800 p-8 rounded-lg border border-gray-700 w-full max-w-md">
                <div className="text-center mb-8">
                    <Lock className="h-12 w-12 mx-auto mb-4 text-blue-500" />
                    <h1 className="text-3xl font-bold text-white mb-2">godEye</h1>
                    <p className="text-gray-400">
                        {isSetup ? 'PiVPN Management Interface' : 'Initial Setup'}
                    </p>
                </div>
                
                {error && (
                    <Alert variant="destructive" className="mb-4">
                        <AlertCircle className="h-4 w-4" />
                        <AlertDescription>{error}</AlertDescription>
                    </Alert>
                )}

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <Label htmlFor="username">Username</Label>
                        <Input
                            id="username"
                            type="text"
                            value={username}
                            onChange={(e) => setUsername(e.target.value)}
                            className={cn(
                                "bg-gray-700 border-gray-600",
                                "focus:border-blue-500 focus:ring-blue-500"
                            )}
                            required
                            disabled={isLoading}
                            autoComplete="username"
                        />
                    </div>
                    
                    <div>
                        <Label htmlFor="password">Password</Label>
                        <Input
                            id="password"
                            type="password"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            className={cn(
                                "bg-gray-700 border-gray-600",
                                "focus:border-blue-500 focus:ring-blue-500"
                            )}
                            required
                            disabled={isLoading}
                            autoComplete={isSetup ? "current-password" : "new-password"}
                        />
                        {!isSetup && password && (
                            <div className="mt-2">
                                <div className="h-2 bg-gray-700 rounded overflow-hidden">
                                    <div 
                                        className={cn("h-full transition-all", getPasswordStrengthColor())}
                                        style={{ width: `${passwordStrength}%` }}
                                    />
                                </div>
                            </div>
                        )}
                    </div>

                    {!isSetup && (
                        <>
                            <div>
                                <Label htmlFor="confirmPassword">Confirm Password</Label>
                                <Input
                                    id="confirmPassword"
                                    type="password"
                                    value={confirmPassword}
                                    onChange={(e) => setConfirmPassword(e.target.value)}
                                    className={cn(
                                        "bg-gray-700 border-gray-600",
                                        "focus:border-blue-500 focus:ring-blue-500"
                                    )}
                                    required
                                    disabled={isLoading}
                                    autoComplete="new-password"
                                />
                            </div>
                            <PasswordRequirements errors={errors} />
                        </>
                    )}

                    <Button
                        type="submit"
                        className="w-full"
                        disabled={isLoading}
                    >
                        {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        {isLoading 
                            ? (isSetup ? 'Logging in...' : 'Setting up...')
                            : (isSetup ? 'Login' : 'Complete Setup')}
                    </Button>

                    {!isSetup && (
                        <p className="text-sm text-gray-400 mt-4">
                            Create your administrator account. Make sure to use a strong password that you can remember.
                        </p>
                    )}
                </form>
            </div>
        </div>
    );
};

export default Login;