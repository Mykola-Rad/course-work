using Bogus;
using GenerateData.Models;
using GenerateData.Utills;
using BCrypt.Net;

namespace GenerateData.Generators
{
    public class UserGenerator : IEntityGenerator<User>
    {
        public UserRole Role { get; set; } = UserRole.StorageKeeper;
        public List<User> Generate(int count, GenerationContext context)
        {
            var userFaker = new Faker<User>()
            .RuleFor(u => u.Username, (f, u) => DataGenerationUtils.GenerateValue(faker => faker.Internet.UserName(), 101, f))
            .RuleFor(u => u.PasswordHash, f => BCrypt.Net.BCrypt.HashPassword("password123"))
            .RuleFor(u => u.Role, f => Role);

            var generatedUsers = DataGenerationUtils.GenerateWithUniqueName(
                    count,
                    userFaker,
                    getName: u => u.Username,
                    setName: (u, name) => u.Username = name
            );

            
            context.AvailableUsernames.AddRange(generatedUsers.Select(u => u.Username));

            if (Role == UserRole.StorageKeeper)
                context.AvailableKeeperUsernames.AddRange(generatedUsers.Select(u => u.Username));

            return generatedUsers;
        }
    }
}
