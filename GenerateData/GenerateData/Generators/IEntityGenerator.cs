namespace GenerateData.Generators
{
    public interface IEntityGenerator<TEntity> where TEntity : class
    {
       List<TEntity> Generate(GenerationContext context, int count = 100);
    }
}
