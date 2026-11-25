import { Body, Controller, Get, Headers, Param, Post } from '@nestjs/common';
import { ApiHeader, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DeviceAuthService } from '../auth/device-auth.service';
import { Public } from '../../common/decorators/public.decorator';
import { PrintJobResultDto } from './dto/printing.dto';
import { PrintJobsService } from './print-jobs.service';

/** Called by the print agent and by POS tablets. Authenticated by X-Device-Key, not by a user session. */
@ApiTags('hardware')
@Controller('print-jobs')
export class PrintJobsController {
  constructor(
    private readonly jobs: PrintJobsService,
    private readonly devices: DeviceAuthService,
  ) {}

  @Public()
  @Get('next')
  @ApiHeader({ name: 'X-Device-Key', required: true })
  @ApiOperation({ summary: 'Claim up to 10 queued print jobs for this device outlet' })
  async next(@Headers('x-device-key') deviceKey?: string) {
    const device = await this.devices.authenticate(deviceKey);
    return this.jobs.next(device);
  }

  @Public()
  @Post(':id/result')
  @ApiHeader({ name: 'X-Device-Key', required: true })
  @ApiOperation({ summary: 'Report the outcome of a print job' })
  async result(
    @Param('id') id: string,
    @Headers('x-device-key') deviceKey: string | undefined,
    @Body() dto: PrintJobResultDto,
  ) {
    const device = await this.devices.authenticate(deviceKey);
    return this.jobs.result(id, device, dto);
  }
}
