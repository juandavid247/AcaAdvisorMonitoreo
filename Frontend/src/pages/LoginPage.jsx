import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from '../api/client';
import { useAuthStore } from '../lib/auth-store';
import empLogo from '../assets/emp.png';

export default function LoginPage() {
  const login = useAuthStore((s) => s.login);
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const res = await api.post('/auth/user', { email, password });
      if (res.data.code !== 200) {
        setError(res.data.message || 'Login failed');
        return;
      }
      login(
        {
          user_name: res.data.user_name,
          full_name: res.data.full_name,
          email: res.data.email,
          user_id: res.data.user_id,
          u_id: res.data.u_id,
          organization_id: res.data.organization_id,
          is_admin: res.data.is_admin,
          is_manager: res.data.is_manager,
          is_teamlead: res.data.is_teamlead,
          is_employee: res.data.is_employee,
          role: res.data.role,
          role_id: res.data.role_id,
          photo_path: res.data.photo_path,
        },
        res.data.data
      );
      navigate('/dashboard', { replace: true });
    } catch (err) {
      setError(err.response?.data?.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#F8FAFC] dark:bg-[#090F1D] px-4 py-10 aca-hex-bg">
      <div className="w-full max-w-md flex flex-col items-center gap-5">
        <img
          src={empLogo}
          alt="ACA ADVISOR S.A.S."
          className="h-32 sm:h-40 w-auto max-w-[360px] object-contain drop-shadow-lg aca-logo-adaptive"
        />

        <div className="w-full rounded-3xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-[#111B2E] p-8 shadow-2xl">
          <div className="text-center">
            <span className="text-xs font-bold uppercase tracking-widest text-[#30A9E3] dark:text-[#38BDF8]">
              ACA ADVISOR S.A.S.
            </span>
            <h2 className="mt-1 text-2xl font-bold text-[#0F7CB9] dark:text-white">Bienvenido</h2>
            <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">Inicia sesión en tu cuenta corporativa</p>
          </div>

          {error && (
            <div className="mt-4 rounded-xl bg-red-50 dark:bg-red-950/60 border border-red-200 dark:border-red-800 p-3 text-sm text-red-700 dark:text-red-200">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <div>
              <label htmlFor="email" className="block text-sm font-semibold text-slate-700 dark:text-slate-100">
                Correo electrónico
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                className="mt-1 block w-full rounded-xl border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 px-3.5 py-2.5 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 shadow-sm focus:border-[#30A9E3] focus:outline-none focus:ring-2 focus:ring-[#30A9E3]/30"
                placeholder="usuario@empresa.com"
              />
            </div>
            <div>
              <label htmlFor="password" className="block text-sm font-semibold text-slate-700 dark:text-slate-100">
                Contraseña
              </label>
              <div className="relative mt-1">
                <input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                  className="block w-full rounded-xl border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-900 px-3.5 py-2.5 pr-10 text-sm text-slate-900 dark:text-white placeholder:text-slate-400 shadow-sm focus:border-[#30A9E3] focus:outline-none focus:ring-2 focus:ring-[#30A9E3]/30"
                  placeholder="Ingresa tu contraseña"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-500 dark:text-slate-300 hover:text-[#30A9E3]"
                  tabIndex={-1}
                >
                  {showPassword ? (
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
                      <line x1="1" y1="1" x2="23" y2="23" />
                    </svg>
                  ) : (
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                  )}
                </button>
              </div>
            </div>
            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-xl bg-gradient-to-r from-[#30A9E3] to-[#0F7CB9] hover:from-[#2597ce] hover:to-[#0c6699] px-4 py-2.5 text-sm font-bold text-white disabled:opacity-50 flex items-center justify-center gap-2 shadow-md"
            >
              {loading && (
                <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
              )}
              {loading ? "Iniciando sesión..." : "Iniciar sesión"}
            </button>
          </form>
        </div>

        <p className="text-center text-xs text-slate-600 dark:text-slate-300">
          © {new Date().getFullYear()} ACA ADVISOR S.A.S. – Todos los derechos reservados.
        </p>
      </div>
    </div>
  );
}
