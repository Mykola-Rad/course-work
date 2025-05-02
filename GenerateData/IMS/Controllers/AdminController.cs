using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using IMS.Models;
using IMS.ViewModels;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.Extensions.Logging;
using IMS.Data;

namespace IMS.Controllers
{
    [Authorize(Roles = nameof(UserRole.owner))]
    public class AdminController : Controller
    {
        private readonly AppDbContext _context; 
        private readonly ILogger<AdminController> _logger; 

        public AdminController(AppDbContext context, ILogger<AdminController> logger) 
        {
            _context = context;
            _logger = logger; 
        }

        // GET: Admin/Users
        public async Task<IActionResult> Users()
        {
            var users = await _context.Users
                                      .Include(u => u.StorageKeeper)
                                      .OrderBy(u => u.Username)
                                      .ToListAsync();
            return View(users);
        }

        // GET: Admin/CreateUser
        public async Task<IActionResult> CreateUser()
        {
            var model = new UserViewModel
            {
                AvailableKeepers = await GetAvailableKeepersListAsync()
            };
            return View(model);
        }

        // POST: Admin/CreateUser
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> CreateUser(UserViewModel model)
        {
            if (await _context.Users.AnyAsync(u => u.Username == model.Username))
            {
                ModelState.AddModelError("Username", "Користувач з таким іменем вже існує.");
            }
            if (!string.IsNullOrEmpty(model.Password) && model.Password != model.ConfirmPassword)
            {
                ModelState.AddModelError("ConfirmPassword", "Пароль та підтвердження не співпадають.");
            }
            if (string.IsNullOrEmpty(model.Password))
            {
                ModelState.AddModelError("Password", "Пароль є обов'язковим при створенні користувача.");
            }
            if (model.Role == UserRole.storage_keeper && string.IsNullOrEmpty(model.SelectedStorageKeeperPhoneNumber))
            {
                ModelState.AddModelError("SelectedStorageKeeperPhoneNumber", "Для ролі 'Комірник' необхідно обрати існуючий профіль комірника.");
            }

            if (ModelState.IsValid)
            {
                string hashedPassword = BCrypt.Net.BCrypt.HashPassword(model.Password);

                var user = new User
                {
                    Username = model.Username,
                    PasswordHash = hashedPassword,
                    Role = model.Role
                };

                _context.Users.Add(user);
                await _context.SaveChangesAsync();

                if (model.Role == UserRole.storage_keeper && !string.IsNullOrEmpty(model.SelectedStorageKeeperPhoneNumber))
                {
                    var keeperToLink = await _context.StorageKeepers.FindAsync(model.SelectedStorageKeeperPhoneNumber);
                    if (keeperToLink != null && keeperToLink.UserId == null)
                    {
                        keeperToLink.UserId = user.UserId;
                        _context.StorageKeepers.Update(keeperToLink);
                        await _context.SaveChangesAsync();
                    }
                    else
                    {
                        _context.Users.Remove(user);
                        await _context.SaveChangesAsync();
                        ModelState.AddModelError("SelectedStorageKeeperPhoneNumber", "Помилка: Обраний комірник вже прив'язаний або не існує.");
                        model.AvailableKeepers = await GetAvailableKeepersListAsync();
                        return View(model);
                    }
                }
                TempData["SuccessMessage"] = $"Користувача {user.Username} успішно створено.";
                return RedirectToAction(nameof(Users));
            }

            model.AvailableKeepers = await GetAvailableKeepersListAsync(model.SelectedStorageKeeperPhoneNumber);
            return View(model);
        }

        // GET: Admin/EditUser/5
        public async Task<IActionResult> EditUser(int? id)
        {
            if (id == null) return NotFound();
            var user = await _context.Users.Include(u => u.StorageKeeper).FirstOrDefaultAsync(u => u.UserId == id);
            if (user == null) return NotFound();

            var model = new UserViewModel
            {
                UserId = user.UserId,
                Username = user.Username,
                Role = user.Role,
                SelectedStorageKeeperPhoneNumber = user.StorageKeeper?.PhoneNumber,
                AvailableKeepers = await GetAvailableKeepersListAsync(user.StorageKeeper?.PhoneNumber)
            };
            return View(model);
        }

        // POST: Admin/EditUser/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> EditUser(int id, UserViewModel model)
        {
            if (id != model.UserId) return NotFound();

            var userToUpdate = await _context.Users.Include(u => u.StorageKeeper).FirstOrDefaultAsync(u => u.UserId == id);
            if (userToUpdate == null) return NotFound();

            // Перевірка унікальності імені (якщо змінилося)
            if (userToUpdate.Username != model.Username && await _context.Users.AnyAsync(u => u.Username == model.Username && u.UserId != id))
            {
                ModelState.AddModelError("Username", "Користувач з таким іменем вже існує.");
            }
            if (!string.IsNullOrEmpty(model.Password) && model.Password != model.ConfirmPassword)
            {
                ModelState.AddModelError("ConfirmPassword", "Пароль та підтвердження не співпадають.");
            }
            if (model.Role == UserRole.storage_keeper && string.IsNullOrEmpty(model.SelectedStorageKeeperPhoneNumber))
            {
                ModelState.AddModelError("SelectedStorageKeeperPhoneNumber", "Для ролі 'Комірник' необхідно обрати існуючий профіль комірника.");
            }

            if (ModelState.IsValid)
            {
                using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    StorageKeeper? previousKeeper = userToUpdate.StorageKeeper;
                    string? previouslyLinkedKeeperPhone = previousKeeper?.PhoneNumber;

                    userToUpdate.Username = model.Username;
                    userToUpdate.Role = model.Role;

                    if (!string.IsNullOrEmpty(model.Password))
                    {
                        userToUpdate.PasswordHash = BCrypt.Net.BCrypt.HashPassword(model.Password);
                    }

                    _context.Users.Update(userToUpdate);
                    await _context.SaveChangesAsync();


                    // --- Логіка оновлення зв'язку ---
                    string? newlySelectedKeeperPhone = model.SelectedStorageKeeperPhoneNumber;

                    // 1. Якщо нова роль НЕ комірник, а раніше був зв'язок -> відв'язуємо
                    if (model.Role != UserRole.storage_keeper && previousKeeper != null)
                    {
                        previousKeeper.UserId = null;
                        _context.StorageKeepers.Update(previousKeeper);
                        await _context.SaveChangesAsync();
                    }
                    // 2. Якщо нова роль - комірник
                    else if (model.Role == UserRole.storage_keeper)
                    {
                        // 2а. Якщо вибраний комірник змінився (або не був вибраний)
                        if (newlySelectedKeeperPhone != previouslyLinkedKeeperPhone)
                        {
                            // Відв'язуємо старого (якщо був)
                            if (previousKeeper != null)
                            {
                                previousKeeper.UserId = null;
                                _context.StorageKeepers.Update(previousKeeper);
                                await _context.SaveChangesAsync();
                            }
                            // Прив'язуємо нового (якщо вибрано)
                            if (!string.IsNullOrEmpty(newlySelectedKeeperPhone))
                            {
                                // Знаходимо за номером телефону
                                var keeperToLink = await _context.StorageKeepers.FindAsync(newlySelectedKeeperPhone);
                                if (keeperToLink != null && keeperToLink.UserId == null) // Перевірка, чи вільний
                                {
                                    keeperToLink.UserId = userToUpdate.UserId;
                                    _context.StorageKeepers.Update(keeperToLink);
                                    await _context.SaveChangesAsync();
                                }
                                else
                                {
                                    // Помилка: зайнятий або не існує
                                    await transaction.RollbackAsync();
                                    ModelState.AddModelError("SelectedStorageKeeperPhoneNumber", "Помилка: Обраний комірник вже прив'язаний або не існує.");
                                    model.AvailableKeepers = await GetAvailableKeepersListAsync(model.SelectedStorageKeeperPhoneNumber); // Перезавантажуємо список
                                    return View(model);
                                }
                            }
                        }
                        // 2б. Якщо вибраний комірник не змінився - нічого не робимо
                    }

                    await transaction.CommitAsync();
                    TempData["SuccessMessage"] = $"Дані користувача {model.Username} успішно оновлено.";
                    return RedirectToAction(nameof(Users));
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    _logger.LogError(ex, "Помилка при оновленні користувача {UserId}", id);
                    ModelState.AddModelError("", "Виникла помилка при збереженні даних.");
                    TempData["ErrorMessage"] = "Не вдалося відредагувати користувача.";
                    model.AvailableKeepers = await GetAvailableKeepersListAsync(model.SelectedStorageKeeperPhoneNumber); 
                    return View(model);
                }
            }

            // Якщо модель не валідна, перезавантажуємо список
            model.AvailableKeepers = await GetAvailableKeepersListAsync(model.SelectedStorageKeeperPhoneNumber);
            return View(model);
        }


        // GET: Admin/DeleteUser/5 - логіка не змінюється
        public async Task<IActionResult> DeleteUser(int? id)
        {
            // Логіка не змінилася значно, показуємо користувача
            if (id == null) return NotFound();
            var user = await _context.Users.FirstOrDefaultAsync(m => m.UserId == id);
            if (user == null) return NotFound();
            return View(user);
        }


        // POST: Admin/DeleteUser/5
        [HttpPost, ActionName("DeleteUser")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteUserConfirmed(int id)
        {
            var userToDelete = await _context.Users.Include(u => u.StorageKeeper).FirstOrDefaultAsync(u => u.UserId == id);
            if (userToDelete == null) return NotFound();

            using var transaction = await _context.Database.BeginTransactionAsync();
            try
            {
                // Відв'язуємо комірника, якщо він був
                if (userToDelete.StorageKeeper != null)
                {
                    userToDelete.StorageKeeper.UserId = null;
                    _context.StorageKeepers.Update(userToDelete.StorageKeeper);
                    // Важливо: Не зберігаємо тут, щоб все було в одній транзакції
                }

                _context.Users.Remove(userToDelete);
                await _context.SaveChangesAsync(); // Зберігаємо видалення User та оновлення Keeper

                await transaction.CommitAsync();
                TempData["SuccessMessage"] = $"Користувача {userToDelete.Username} успішно видалено.";
                return RedirectToAction(nameof(Users));
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                _logger.LogError(ex, "Помилка при видаленні користувача {UserId}", id);
                TempData["ErrorMessage"] = "Не вдалося видалити користувача.";
                return RedirectToAction(nameof(Users));
            }
        }


        // Допоміжний метод для отримання списку - тепер використовує string ключ і текст
        private async Task<IEnumerable<SelectListItem>> GetAvailableKeepersListAsync(string? currentKeeperPhone = null)
        {
            var availableKeepers = await _context.StorageKeepers
                // Вибираємо тих, хто вільний (UserId == null) АБО поточного прив'язаного
                .Where(sk => sk.UserId == null || sk.PhoneNumber == currentKeeperPhone)
                .OrderBy(sk => sk.LastName).ThenBy(sk => sk.FirstName)
                .Select(sk => new SelectListItem
                {
                    Value = sk.PhoneNumber, // Значення - номер телефону
                    Text = $"{sk.LastName} {sk.FirstName} ({sk.PhoneNumber})" // Текст - ПІБ + телефон для ясності
                })
                .ToListAsync();

            return availableKeepers;
        }
    }
}