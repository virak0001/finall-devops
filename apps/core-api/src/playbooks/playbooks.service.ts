import { Injectable, NotFoundException, OnApplicationBootstrap } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DeepPartial, Repository } from 'typeorm';
import { CreatePlaybookDto } from './dto/create-playbook.dto';
import { UpdatePlaybookDto } from './dto/update-playbook.dto';
import { playbookCategories, PlaybookCategory } from './playbook.constants';
import { Playbook } from './playbook.entity';

@Injectable()
export class PlaybooksService implements OnApplicationBootstrap {
  private readonly starterPlaybooks: DeepPartial<Playbook>[] = [
    {
      title: 'Blue/green release orchestration',
      description:
        'Create a release strategy that shifts traffic safely between active and standby versions using container health checks.',
      category: 'delivery',
      difficulty: 'advanced',
      status: 'practicing',
    },
    {
      title: 'Observability scorecard',
      description:
        'Wire logs, metrics, and tracing together so every deployment is measured against a clear reliability baseline.',
      category: 'observability',
      difficulty: 'intermediate',
      status: 'validated',
    },
    {
      title: 'Swarm rollback rehearsal',
      description:
        'Practice rolling updates, automatic rollback, and failure simulation until recovery steps are routine and documented.',
      category: 'resilience',
      difficulty: 'advanced',
      status: 'practicing',
    },
    {
      title: 'Secret rotation checklist',
      description:
        'Document how credentials move through Docker, runtime config, and database users without leaking into images.',
      category: 'security',
      difficulty: 'intermediate',
      status: 'planned',
    },
  ];

  constructor(
    @InjectRepository(Playbook)
    private readonly playbookRepository: Repository<Playbook>,
  ) {}

  async onApplicationBootstrap() {
    await this.seedDefaults();
  }

  async findAll() {
    return this.playbookRepository.find({
      order: {
        createdAt: 'DESC',
      },
    });
  }

  async create(createPlaybookDto: CreatePlaybookDto) {
    const playbook = this.playbookRepository.create(createPlaybookDto);
    return this.playbookRepository.save(playbook);
  }

  async update(id: string, dto: UpdatePlaybookDto) {
    const playbook = await this.playbookRepository.findOne({ where: { id } });
    if (!playbook) throw new NotFoundException(`Playbook ${id} not found`);
    Object.assign(playbook, dto);
    return this.playbookRepository.save(playbook);
  }

  async remove(id: string) {
    const playbook = await this.playbookRepository.findOne({ where: { id } });
    if (!playbook) throw new NotFoundException(`Playbook ${id} not found`);
    await this.playbookRepository.remove(playbook);
    return { deleted: true };
  }

  async getSummary() {
    const [total, practicing, validated, recent, categories] =
      await Promise.all([
        this.playbookRepository.count(),
        this.playbookRepository.countBy({ status: 'practicing' }),
        this.playbookRepository.countBy({ status: 'validated' }),
        this.playbookRepository.find({
          take: 3,
          order: {
            createdAt: 'DESC',
          },
        }),
        Promise.all(
          playbookCategories.map(async (category) => ({
            key: category,
            total: await this.playbookRepository.countBy({ category }),
          })),
        ),
      ]);

    return {
      total,
      practicing,
      validated,
      recent,
      categories,
    };
  }

  private async seedDefaults() {
    const existingPlaybooks = await this.playbookRepository.count();

    if (existingPlaybooks > 0) {
      return;
    }

    await this.playbookRepository.save(
      this.starterPlaybooks.map((playbook) => ({
        ...playbook,
        category: playbook.category as PlaybookCategory,
      })),
    );
  }
}
