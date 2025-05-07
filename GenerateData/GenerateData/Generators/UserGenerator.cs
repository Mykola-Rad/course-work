using Bogus;
using GenerateData.Models;
using GenerateData.Utills;

namespace GenerateData.Generators
{
    public class UserGenerator : IEntityGenerator<User>
    {
        private const string _defaultRole = "storage_keeper";
        public string Role { get; set; } = _defaultRole;
        public List<User> Generate(GenerationContext context, int count = 100)
        {
            var userFaker = new Faker<User>()
            .RuleFor(u => u.Username, (f, u) => DataGenerationUtils.GenerateValue(faker => faker.Internet.UserName(), 101, f))
            .RuleFor(u => u.PasswordHash, f => BCrypt.Net.BCrypt.HashPassword(f.Internet.Password()))
            .RuleFor(u => u.Role, f => Role);

            var generatedUsers = DataGenerationUtils.GenerateWithUniqueName(
                    count,
                    userFaker,
                    getName: u => u.Username,
                    setName: (u, name) => u.Username = name
            );

            return generatedUsers;
        }


    }
}
