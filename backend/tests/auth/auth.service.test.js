require('dotenv').config();
const bcrypt = require('bcrypt');
jest.mock('../../models', () => ({ Usuario: { findOne: jest.fn() }, Rol: {} }));
const { Usuario } = require('../../models');
const authService = require('../../src/modules/auth/auth.service');

describe('authService.login', () => {
  it('rechaza un correo que no existe', async () => {
    Usuario.findOne.mockResolvedValueOnce(null);
    await expect(authService.login('no-existe@x.com', 'cualquiera'))
      .rejects.toMatchObject({ code: 'CREDENCIALES_INVALIDAS' });
  });

  it('genera un token cuando la contraseña es correcta', async () => {
    const hash = await bcrypt.hash('Admin123', 10);
    const usuarioMock = {
      id: 1,
      nombre: 'Administrador Inicial',
      passwordHash: hash,
      intentosFallidos: 0,
      bloqueadoHasta: null,
      Rol: { nombre: 'administrador' },
      update: jest.fn(),
    };
    Usuario.findOne.mockResolvedValueOnce(usuarioMock);
    const resultado = await authService.login('a@a.com', 'Admin123');
    expect(resultado.token).toBeDefined();
  });
});
